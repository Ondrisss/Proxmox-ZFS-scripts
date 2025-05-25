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

# Установка ZFS
echo "Установка ZFS..."
apt install -y zfsutils-linux

# Определение дисков для ZFS, исключая смонтированные и хотплаг
DISKS=$(lsblk -dn -o NAME,HOTPLUG | while read name hotplug; do
    dev="/dev/$name"

    # Пропускаем хотплаг-устройства (USB, съёмные и т.д.)
    [ "$hotplug" -eq 1 ] && continue

    # Пропускаем, если есть смонтированные точки
    mountpoint=$(lsblk -no MOUNTPOINT "$dev" | grep -v '^$')
    [ -n "$mountpoint" ] && continue

    echo "$dev"
done)

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
  zfs set snapdir=visible $pool_name
  echo "ZFS pool создан:"
  zpool status
fi

echo "Настройка завершена успешно!"


