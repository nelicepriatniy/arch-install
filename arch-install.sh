#!/bin/bash

# Установка русского шрифта для консоли
setfont cyr-sun16
echo -e "\e[1;32mУстановлен шрифт cyr-sun16\e[0m"

# Проверка подключения к интернету
echo "Проверка интернет-соединения..."
if ! ping -c 3 archlinux.org &> /dev/null; then
    echo -e "\e[1;31mОшибка: Нет подключения к интернету!\e[0m"
    echo "1. Wi-Fi: используйте iwctl"
    echo "   iwctl"
    echo "   [iwd]# station wlan0 scan"
    echo "   [iwd]# station wlan0 connect SSID"
    echo "   [iwd]# exit"
    echo "2. Проводное: dhcpcd"
    exit 1
fi

# Запрос диска для разметки
echo -e "\n\e[1;33mДоступные диски:\e[0m"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
echo ""
read -p "Введите диск для разметки (например, /dev/sda): " disk

# Проверка существования диска
if [ ! -b "$disk" ]; then
    echo -e "\e[1;31mОшибка: диск $disk не существует!\e[0m"
    exit 1
fi

# Предупреждение о потере данных
echo -e "\n\e[1;31mВНИМАНИЕ: Все данные на $disk будут уничтожены!\e[0m"
read -p "Продолжить? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Установка отменена."
    exit 0
fi

# Разметка диска с помощью fdisk
echo -e "\n\e[1;32mСоздание разделов...\e[0m"
(
echo g              # Создать новую GPT таблицу
echo n              # Новый раздел
echo 1              # Раздел 1
echo                # Начало по умолчанию
echo +1G            # Размер 1G
echo t              # Сменить тип
echo 1              # EFI System
echo n              # Новый раздел
echo 2              # Раздел 2
echo                # Начало по умолчанию
echo +4G            # Размер 4G
echo t              # Сменить тип
echo 2              # Выбрать раздел 2
echo 19             # Linux Swap
echo n              # Новый раздел
echo 3              # Раздел 3
echo                # Начало по умолчанию
echo                # Весь оставшийся диск
echo t              # Сменить тип
echo 3              # Выбрать раздел 3
echo 20             # Linux filesystem
echo w              # Записать изменения
) | sudo fdisk "$disk"

# Определение созданных разделов
efi_part="${disk}1"
swap_part="${disk}2"
root_part="${disk}3"

# Форматирование разделов
echo -e "\n\e[1;32mФорматирование разделов...\e[0m"
sudo mkfs.fat -F 32 "$efi_part"
sudo mkswap "$swap_part"
sudo mkfs.ext4 -F "$root_part"  # -F для принудительного форматирования

# Монтирование разделов
echo -e "\n\e[1;32mМонтирование разделов...\e[0m"
sudo mount "$root_part" /mnt
sudo mount --mkdir "$efi_part" /mnt/boot
sudo swapon "$swap_part"

# Установка базовой системы
echo -e "\n\e[1;32mУстановка базовой системы...\e[0m"
sudo pacstrap -K /mnt base base-devel sudo efibootmgr os-prober ntfs-3g networkmanager \
grub xdg-user-dirs linux linux-firmware micro dhcpcd terminus-font

# Генерация fstab
echo -e "\n\e[1;32mГенерация fstab...\e[0m"
sudo genfstab -U /mnt >> /mnt/etc/fstab

# Настройка системы в chroot
echo -e "\n\e[1;32mНастройка системы...\e[0m"
arch-chroot /mnt /bin/bash <<EOF
# Установка шрифта для консоли
echo "FONT=cyr-sun16" > /etc/vconsole.conf
setfont cyr-sun16

# Установка часового пояса
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# Настройка локали
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

# Установка имени хоста
echo "Введите имя хоста:"
read hostName
echo "\$hostName" > /etc/hostname

# Создание файла hosts
echo "127.0.0.1  localhost" >> /etc/hosts
echo "::1        localhost" >> /etc/hosts
echo "127.0.1.1  \$hostName.localdomain  \$hostName" >> /etc/hosts

# Установка пароля root
echo "Установка пароля root:"
passwd

# Установка загрузчика
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Включение NetworkManager
systemctl enable NetworkManager

exit
EOF

# Завершение установки
echo -e "\n\e[1;32mЗавершение установки...\e[0m"
sudo umount -R /mnt
echo -e "\e[1;33mУстановка завершена! Система будет перезагружена через 10 секунд...\e[0m"
echo -e "\e[1;33mНе забудьте извлечь установочный носитель!\e[0m"
sleep 10
sudo reboot