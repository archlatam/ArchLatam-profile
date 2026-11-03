#!/bin/bash

# autor: archlatam Core Linux

systemctl enable NetworkManager
systemctl enable plasmalogin

xdg-user-dirs-update || true
