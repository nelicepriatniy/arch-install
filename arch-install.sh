#!/bin/bash

# Запрос диска для разметки
lsblk
read -p "Введите диск для разметки (например, /dev/sda): " disk

# Проверка существования диска
if [ ! -b "$disk" ]; then
    echo "Ошибка: диск $disk не существует!"
    exit 1
fi

# Разметка диска с помощью fdisk
echo "Создание разделов..."
echo -e "g\nn\n\n\n+1G\nt\n1\nn\n\n\n+4G\nt\n2\n19\nn\n\n\n\nw" | sudo fdisk "$disk"

# Определение созданных разделов
efi_part="${disk}1"
swap_part="${disk}2"
root_part="${disk}3"

# Форматирование разделов
echo "Форматирование разделов..."
sudo mkfs.fat -F 32 "$efi_part"
sudo mkswap "$swap_part"
sudo mkfs.ext4 "$root_part"

# Монтирование разделов
echo "Монтирование разделов..."
sudo mount "$root_part" /mnt
sudo mount --mkdir "$efi_part" /mnt/boot
sudo swapon "$swap_part"

# Установка базовой системы
echo "Установка базовой системы..."
sudo pacstrap -K /mnt base sudo efibootmgr os-prober ntfs-3g networkmanager grub xdg-user-dirs linux linux-firmware micro dhcpcd

# Генерация fstab
echo "Генерация fstab..."
sudo genfstab -U /mnt >> /mnt/etc/fstab

# Настройка системы в chroot
echo "Настройка системы..."
arch-chroot /mnt /bin/bash <<EOF
# Установка часового пояса
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# Настройка локали
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

# Установка имени хоста
read -p "Введите имя хоста: " hostName
echo "$hostName" > /etc/hostname

# Установка пароля root
echo "Установка пароля root:"
passwd

# Установка загрузчика
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

exit
EOF

# Завершение установки
echo "Завершение установки..."
sudo umount -R /mnt
echo "Установка завершена. Система будет перезагружена через 5 секунд..."
sleep 5
sudo reboot