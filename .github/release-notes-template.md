# CrowPanel Advanced ESP32-P4/C6 Upgrade {{RELEASE_TAG}}

This release contains prebuilt firmware images and a one-step flashing script for both supported targets.

## Included Targets
- crowpanel-p4-50
- crowpanel-p4-70-90-101

## ESP32-C6 Firmware Source
The bundled C6 network adapter firmware was fetched from:
- Repository: https://github.com/esphome/esp-hosted-firmware/releases
- Release tag: {{C6_RELEASE_TAG}}
- File: network_adapter_esp32c6.bin

Note: `network_adapter_esp32c6.bin` is embedded in `littlefs.bin` during the build.

## Flashing
Each target artifact bundle includes an `install.sh` script and all required binaries.

Example:
```bash
chmod +x install.sh
./install.sh /dev/ttyUSB0 921600
```

## Flash Layout (install.sh)
- 0x2000 -> bootloader.bin
- 0x8000 -> partitions.bin
- 0xD000 -> ota_data_initial.bin (blank image)
- 0x10000 -> firmware.bin
- 0x410000 -> littlefs.bin (holds network_adapter_esp32c6.bin)

## Notes
- Flashing requires `esptool` (or `esptool.py`, or Python module `esptool`).
- Replace `/dev/ttyUSB0` with your board serial port.
