#!/bin/bash
# ZFS Storage Configuration Script for Proxmox VE
# Настраивает ZFS хранилище и сетевые мосты

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен выполняться от имени root. Используйте sudo."
  exit 1
fi

# Проверка установки Proxmox
if ! dpkg -l | grep -q proxmox-ve; then
  echo "Proxmox VE не установлен. Сначала запустите Proxmox_setup.sh"
  exit 1
fi

# Функция для обработки ошибок
handle_error() {
  echo "Ошибка в строке $1. Код выхода $2"
  exit $2
}

trap 'handle_error $LINENO $?' ERR

# Определение сетевого интерфейса
PHYSICAL_INTERFACE=$(ip -o link show | awk '$2 !~ /lo|docker|veth|virbr|vmbr/ {print $2}' | cut -d":" -f1 | head -n 1)

if [ -z "$PHYSICAL_INTERFACE" ]; then
  echo "Не удалось определить физический интерфейс."
  exit 1
fi

echo "Найден физический интерфейс: $PHYSICAL_INTERFACE"

# Получение сетевых параметров
HOST_IP=$(hostname -I | cut -d' ' -f1)
HOST_NETMASK=$(ip addr show $PHYSICAL_INTERFACE | grep "inet" | awk '{print $2}' | cut -d'/' -f2)
HOST_GATEWAY=$(ip route | grep default | awk '{print $3}')

# Резервное копирование сетевых настроек
echo "Создание резервной копии сетевых настроек..."
cp /etc/network/interfaces /etc/network/interfaces.bak

# Настройка моста
echo "Настройка сетевого моста..."
cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $PHYSICAL_INTERFACE
iface $PHYSICAL_INTERFACE inet manual

auto vmbr0
iface vmbr0 inet static
  address $HOST_IP
  netmask $HOST_NETMASK
  gateway $HOST_GATEWAY
  bridge_ports $PHYSICAL_INTERFACE
  bridge_stp off
  bridge_fd 0
EOF

# Перезапуск сети
echo "Применение сетевых настроек..."
systemctl restart networking

# Установка ZFS
echo "Установка ZFS..."
apt install -y zfsutils-linux

# Определение дисков для ZFS
echo "Поиск доступных дисков..."
DISKS=$(lsblk -d -o NAME,ROTA | grep -v NAME | awk '{print "/dev/"$1}')
echo "Найдены диски:"
echo "$DISKS"

# Создание ZFS пула
read -p "Создать ZFS pool? (y/n): " create_pool
if [[ "$create_pool" =~ ^[yY] ]]; then
  read -p "Введите имя для ZFS pool: " pool_name
  echo "Выберите тип RAID:"
  echo "1) stripe (без избыточности)"
  echo "2) mirror (зеркалирование)"
  echo "3) raidz1 (аналог RAID5)"
  echo "4) raidz2 (аналог RAID6)"
  read -p "Ваш выбор (1-4): " raid_type
  
  case $raid_type in
    1) raid="";;
    2) raid="mirror";;
    3) raid="raidz1";;
    4) raid="raidz2";;
    *) echo "Неверный выбор"; exit 1;;
  esac
  
  echo "Выберите диски (разделяйте пробелами):"
  select_disk=1
  for disk in $DISKS; do
    echo "$select_disk) $disk"
    ((select_disk++))
  done
  
  read -p "Номера дисков: " selected_disks
  disk_list=""
  for num in $selected_disks; do
    disk=$(echo "$DISKS" | sed -n "${num}p")
    disk_list+=" $disk"
  done
  
  echo "Создание ZFS pool $pool_name..."
  zpool create -f -o ashift=12 $pool_name $raid $disk_list
  
  # Настройка ZFS для Proxmox
  echo "Настройка ZFS для Proxmox..."
  zfs set compression=lz4 $pool_name
  zfs set atime=off $pool_name
  
  echo "ZFS pool создан:"
  zpool status
fi

echo "Настройка завершена успешно!"


