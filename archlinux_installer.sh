#!/bin/bash

# Variables (Modifica según necesidad)
DISK="/dev/nvme0n1"  # Cambia esto según tu disco principal
USERNAME="global"
PASSWORD="admin"
HOSTNAME="archlinux"
LOCALE="en_US.UTF-8"
TIMEZONE="America/Lima"
DESKTOP_ENV="kde"  # Cambia a "gnome" si prefieres GNOME

# Confirmación antes de formatear el disco
echo "¡¡¡ATENCIÓN!!! Se borrará TODO en $DISK. ¿Seguro? (yes/no)"
read confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Instalación cancelada."
    exit 1
fi

# Verificar si el sistema está en modo UEFI
echo "Verificando si el sistema está en modo UEFI..."
if [[ ! -d /sys/firmware/efi ]]; then
    echo "Error: El sistema no está en modo UEFI. Asegúrate de habilitar UEFI en la BIOS."
    exit 1
fi

# Particionado del disco
echo "Particionando $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 512MiB 130.5GiB
parted -s "$DISK" mkpart primary ext4 130.5GiB 170.5GiB
parted -s "$DISK" mkpart primary linux-swap 170.5GiB 180.5GiB
parted -s "$DISK" mkpart primary ext4 180.5GiB 100%

# Formateo de las particiones
mkfs.fat -F32 "${DISK}p1"
mkfs.ext4 "${DISK}p2"
mkfs.ext4 "${DISK}p3"
mkswap "${DISK}p4"
mkfs.ext4 "${DISK}p5"

# Montaje de las particiones
mount "${DISK}p2" /mnt
mkdir -p /mnt/boot
mount "${DISK}p1" /mnt/boot
mkdir -p /mnt/home
mount "${DISK}p3" /mnt/home
swapon "${DISK}p4"
mkdir -p /mnt/var
mount "${DISK}p5" /mnt/var

# Instalación del sistema base
echo "Instalando el sistema base..."
pacstrap /mnt base linux linux-firmware vim sudo networkmanager systemd-boot efibootmgr

# Generar fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot en el sistema instalado
echo "Configurando el sistema..."
arch-chroot /mnt /bin/bash <<EOF

# Configuración de zona horaria
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configuración de locales
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=la-latin1" > /etc/vconsole.conf

# Configuración del hostname
echo "$HOSTNAME" > /etc/hostname

# Configuración de red
systemctl enable NetworkManager

# Instalación de systemd-boot
bootctl --path=/boot install

# Configuración del cargador de arranque
echo "title   Arch Linux" > /boot/loader/entries/arch.conf
echo "linux   /vmlinuz-linux" >> /boot/loader/entries/arch.conf
echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
echo "options root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK}p2) rw" >> /boot/loader/entries/arch.conf

# Asegurar que el sistema detecte systemd-boot
efibootmgr -c -d $DISK -p 1 -L "Arch Linux" -l "\\EFI\\BOOT\\BOOTX64.EFI"

# Creación del usuario y permisos
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers

# Instalación de entorno gráfico
if [[ "$DESKTOP_ENV" == "kde" ]]; then
    pacman -S --noconfirm plasma-meta kde-applications sddm
    systemctl enable sddm
elif [[ "$DESKTOP_ENV" == "gnome" ]]; then
    pacman -S --noconfirm gnome gdm
    systemctl enable gdm
fi

EOF

# Desmontar y reiniciar
echo "Instalación completada. Reiniciando..."
umount -R /mnt
reboot