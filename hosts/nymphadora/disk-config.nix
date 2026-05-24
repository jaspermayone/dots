# GPT + BIOS/GRUB layout for SeaBIOS Proxmox VMs.
# The EF02 partition gives GRUB space to embed its core on a GPT disk.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02"; # GRUB BIOS boot — no filesystem needed
          priority = 1;
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
