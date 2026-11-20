# RTL8723FS / RTL8733BS Bluetooth firmware (UART)

The GameMT E5 Plus radio is an RTL8733BS. Its Bluetooth core identifies as an
RTL8723F (LMP subversion 0x8723, HCI revision 0x000f, project ID 19) and is
wired to UART1, so it takes Realtek's UART ("rtlbt") firmware for the 8723FS.

Source: Realtek's Bluetooth Linux package as published in
https://github.com/radxa/rtkbt at commit 72ef9b75374fdde945e0a19f6aba68e13d4d426d,
`rtkbt-firmware/lib/firmware/rtlbt/rtl8723fs_fw` and `rtl8723fs_config`,
renamed to the names btrtl requests (see
patches/e5plus/kernel/0004-btrtl-support-rtl8723f-uart.patch).

sha256:
    69e8fb60844099be0bd1c65047f18b920db089423d0bae1281cd0312c6b01667  rtl8723fs_fw.bin
    efa8915db59c5bc30aaa23e1f264656bbf425fcaf091db0954c27752a1d8f7a0  rtl8723fs_config.bin
