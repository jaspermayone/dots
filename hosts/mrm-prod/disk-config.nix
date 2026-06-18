# GPT + BIOS/GRUB layout for SeaBIOS Proxmox VMs.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
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
