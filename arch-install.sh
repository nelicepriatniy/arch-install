#!/bin/bash

# Установка русского шрифта для консоли
setfont cyr-sun16
echo -e "\e[1;32m[✓] Установлен шрифт cyr-sun16\e[0m"

# Проверка UEFI
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo -e "\e[1;31m[✗] Ошибка: Система не загрузилась в режиме UEFI!\e[0m"
    echo "Пожалуйста, перезагрузитесь в UEFI режиме"
    exit 1
else
    echo -e "\e[1;32m[✓] Система загружена в режиме UEFI\e[0m"
fi

# Проверка подключения к интернету
echo -e "\n\e[1;33m[i] Проверка интернет-соединения...\e[0m"
if ! ping -c 3 archlinux.org &> /dev/null; then
    echo -e "\e[1;31m[✗] Ошибка: Нет подключения к интернету!\e[0m"
    echo "1. Wi-Fi: используйте iwctl"
    echo "   iwctl"
    echo "   [iwd]# station wlan0 scan"
    echo "   [iwd]# station wlan0 connect SSID"
    echo "   [iwd]# exit"
    echo "2. Проводное: dhcpcd"
    exit 1
else
    echo -e "\e[1;32m[✓] Интернет-соединение активно\e[0m"
fi

# Запрос диска для разметки
echo -e "\n\e[1;33m[i] Доступные диски:\e[0m"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
echo ""
read -p "Введите диск для разметки (например, /dev/sda): " disk

# Проверка существования диска
if [ ! -b "$disk" ]; then
    echo -e "\e[1;31m[✗] Ошибка: диск $disk не существует!\e[0m"
    exit 1
fi

# Предупреждение о потере данных
echo -e "\n\e[1;31m[!] ВНИМАНИЕ: Все данные на $disk будут уничтожены!\e[0m"
read -p "Продолжить? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Установка отменена."
    exit 0
fi

# Разметка диска
echo -e "\n\e[1;32m[→] Создание разделов...\e[0m"
(
echo g        
echo n         
echo 1          
echo             
echo +1G    
echo t          
echo 1           
echo n           
echo 2            
echo            
echo +4G      
echo t         
echo 2           
echo 19          
echo n            
echo 3             
echo                
echo             
echo t              
echo 3              
echo 20             
echo w              
) | sudo fdisk -W always "$disk" || { echo -e "\e[1;31m[✗] Ошибка при разметке диска!\e[0m"; exit 1; }

# Синхронизация и ожидание появления разделов
partprobe "$disk"
sleep 2

# Определение созданных разделов
efi_part="${disk}1"
swap_part="${disk}2"
root_part="${disk}3"

# Проверка существования разделов
echo -e "\n\e[1;33m[i] Проверка созданных разделов:\e[0m"
for part in "$efi_part" "$swap_part" "$root_part"; do
    if [ ! -b "$part" ]; then
        echo -e "\e[1;31m[✗] Раздел $part не найден!\e[0m"
        exit 1
    else
        echo -e "\e[1;32m[✓] Найден раздел $part\e[0m"
    fi
done

# Форматирование разделов
echo -e "\n\e[1;32m[→] Форматирование разделов...\e[0m"
sudo mkfs.fat -F 32 "$efi_part" || { echo -e "\e[1;31m[✗] Ошибка форматирования EFI раздела!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] EFI раздел отформатирован\e[0m"

sudo mkswap "$swap_part" || { echo -e "\e[1;31m[✗] Ошибка создания swap!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Swap раздел создан\e[0m"

sudo mkfs.ext4 -F "$root_part" || { echo -e "\e[1;31m[✗] Ошибка форматирования root раздела!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Root раздел отформатирован\e[0m"

# Монтирование разделов
echo -e "\n\e[1;32m[→] Монтирование разделов...\e[0m"
sudo mount "$root_part" /mnt || { echo -e "\e[1;31m[✗] Ошибка монтирования root раздела!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Root раздел смонтирован\e[0m"

sudo mount --mkdir "$efi_part" /mnt/boot || { echo -e "\e[1;31m[✗] Ошибка монтирования EFI раздела!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] EFI раздел смонтирован в /mnt/boot\e[0m"

sudo swapon "$swap_part" || { echo -e "\e[1;31m[✗] Ошибка активации swap!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Swap активирован\e[0m"

# Установка базовой системы
echo -e "\n\e[1;32m[→] Установка базовой системы...\e[0m"
sudo pacman -Sy --noconfirm || { echo -e "\e[1;31m[✗] Ошибка синхронизации репозиториев!\e[0m"; exit 1; }

sudo pacstrap -K /mnt base base-devel linux linux-firmware sudo efibootmgr os-prober \
ntfs-3g networkmanager grub xdg-user-dirs micro dhcpcd terminus-font || { 
    echo -e "\e[1;31m[✗] Ошибка установки базовой системы!\e[0m"
    exit 1
}
echo -e "\e[1;32m[✓] Базовая система установлена\e[0m"

# Генерация fstab
echo -e "\n\e[1;32m[→] Генерация fstab...\e[0m"
sudo genfstab -U /mnt > /mnt/etc/fstab || { echo -e "\e[1;31m[✗] Ошибка генерации fstab!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Fstab сгенерирован\e[0m"

# Настройка системы в chroot
echo -e "\n\e[1;32m[→] Настройка системы...\e[0m"

# Подготовка chroot-скрипта
cat << 'EOF' > /mnt/chroot_script.sh
#!/bin/bash

# Установка шрифта для консоли
echo "FONT=cyr-sun16" > /etc/vconsole.conf
setfont cyr-sun16
echo -e "\e[1;32m[✓] Шрифт консоли настроен\e[0m"

# Установка часового пояса
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime || { echo -e "\e[1;31m[✗] Ошибка установки часового пояса!\e[0m"; exit 1; }
hwclock --systohc || { echo -e "\e[1;31m[✗] Ошибка синхронизации часов!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Часовой пояс настроен\e[0m"

# Настройка локали
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
locale-gen || { echo -e "\e[1;31m[✗] Ошибка генерации локалей!\e[0m"; exit 1; }
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo -e "\e[1;32m[✓] Локали настроены\e[0m"

# Установка имени хоста
echo "Введите имя хоста: "
read hostName
echo "$hostName" > /etc/hostname || { echo -e "\e[1;31m[✗] Ошибка записи hostname!\e[0m"; exit 1; }

# Настройка hosts
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostName.localdomain $hostName
HOSTS_EOF
echo -e "\e[1;32m[✓] Файл hosts настроен\e[0m"

# Установка пароля root
echo "Установка пароля root:"
until passwd; do
    echo -e "\e[1;31m[✗] Ошибка установки пароля! Попробуйте снова.\e[0m"
done
echo -e "\e[1;32m[✓] Пароль root установлен\e[0m"

# Установка загрузчика
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck || { 
    echo -e "\e[1;31m[✗] Ошибка установки GRUB!\e[0m"
    echo "Проверьте:"
    echo "1. Монтирование EFI раздела в /boot"
    echo "2. Наличие пакетов grub и efibootmgr"
    exit 1
}
echo -e "\e[1;32m[✓] GRUB установлен\e[0m"

grub-mkconfig -o /boot/grub/grub.cfg || { echo -e "\e[1;31m[✗] Ошибка генерации конфига GRUB!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Конфиг GRUB сгенерирован\e[0m"

# Включение NetworkManager
systemctl enable NetworkManager || { echo -e "\e[1;31m[✗] Ошибка включения NetworkManager!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] NetworkManager включен\e[0m"

# Создание пользователя
read -p "Создать обычного пользователя? (y/N): " create_user
if [ "$create_user" = "y" ] || [ "$create_user" = "Y" ]; then
    read -p "Введите имя пользователя: " username
    useradd -m -G wheel,audio,video,storage -s /bin/bash "$username" || { echo -e "\e[1;31m[✗] Ошибка создания пользователя!\e[0m"; exit 1; }
    echo "Установка пароля для $username:"
    until passwd "$username"; do
        echo -e "\e[1;31m[✗] Ошибка установки пароля! Попробуйте снова.\e[0m"
    done
    
    # Настройка sudo
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers || { echo -e "\e[1;31m[✗] Ошибка настройки sudo!\e[0m"; exit 1; }
    echo -e "\e[1;32m[✓] Пользователь $username создан и добавлен в sudo\e[0m"
fi

# Проверка установки GRUB
if [ ! -f /boot/grub/grub.cfg ]; then
    echo -e "\e[1;31m[✗] КРИТИЧЕСКАЯ ОШИБКА: GRUB не установлен!\e[0m"
    echo "Попробуйте вручную:"
    echo "1. arch-chroot /mnt"
    echo "2. grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
    echo "3. grub-mkconfig -o /boot/grub/grub.cfg"
    exit 1
fi

exit 0
EOF

# Даем права и запускаем chroot-скрипт
chmod +x /mnt/chroot_script.sh
arch-chroot /mnt /bin/bash -c "./chroot_script.sh" || { 
    echo -e "\e[1;31m[✗] Ошибка в chroot-скрипте!\e[0m"
    echo "Для ручного исправления выполните:"
    echo "arch-chroot /mnt"
    exit 1
}

# Финализация установки
echo -e "\n\e[1;32m[✓] Настройка системы завершена\e[0m"

# Завершение установки
echo -e "\n\e[1;32m[→] Завершение установки...\e[0m"
sudo umount -R /mnt || { echo -e "\e[1;31m[✗] Ошибка размонтирования!\e[0m"; exit 1; }
echo -e "\e[1;32m[✓] Размонтирование выполнено\e[0m"

echo -e "\n\e[1;33m==============================================\e[0m"
echo -e "\e[1;32m[✓] УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!\e[0m"
echo -e "\e[1;33mСистема будет перезагружена через 10 секунд...\e[0m"
echo -e "\e[1;33mНе забудьте извлечь установочный носитель!\e[0m"
echo -e "\e[1;33m==============================================\e[0m"

sleep 10
sudo reboot
