#!/bin/bash
# Proxmox VE Installation Script for Debian 12
# Автоматизирует установку и базовую настройку Proxmox VE

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен выполняться от имени root. Используйте sudo."
  exit 1
fi

# Проверка версии Debian
if ! grep -q "Debian GNU/Linux 12" /etc/os-release; then
  echo "Этот скрипт предназначен только для Debian 12 (Bookworm)"
  exit 1
fi

# Функция для обработки ошибок
handle_error() {
  echo "Ошибка в строке $1. Код выхода $2"
  exit $2
}

trap 'handle_error $LINENO $?' ERR

# Обновление системы
echo "Обновление системы..."
apt update && apt full-upgrade -y

# Установка зависимостей
echo "Установка необходимых пакетов..."
apt install -y curl wget gnupg

# Добавление репозитория Proxmox
echo "Настройка репозиториев Proxmox..."
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list

# Импорт ключа
date
apt install chrony -y
systemctl restart chrony
timedatectl set-ntp true
echo "Импорт ключа Proxmox..."
{
  wget --no-check-certificate https://download.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg || 
  curl -k -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://download.proxmox.com/debian/proxmox-release-bookworm.gpg
} || {
  echo "Не удалось загрузить GPG ключ. Пробуем альтернативный метод..."
  wget http://download.proxmox.com/debian/proxmox-ve-release-6.x.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
# Обновление пакетов
echo "Обновление списка пакетов..."
apt update

# Установка Proxmox VE
echo "Установка Proxmox VE..."
apt install -y proxmox-ve postfix open-iscsi chrony

# Отключение подписки enterprise
echo "Отключение уведомления о подписке..."
sed -i "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

# Настройка хоста
echo "Настройка имени хоста..."
HOSTNAME=$(hostname)
echo "127.0.0.1 $HOSTNAME" >> /etc/hosts

# Перезагрузка
echo "Установка завершена успешно."
read -p "Перезагрузить сейчас? (y/n): " answer
if [[ "$answer" =~ ^[yY] ]]; then
  reboot
else
  echo "Перезагрузите систему вручную командой 'reboot'"
fi