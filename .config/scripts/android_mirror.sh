#!/bin/bash
# Espelha tela do Android via scrcpy com configurações otimizadas
# Desliga a tela do celular enquanto espelha e religa ao sair

# Verifica se há dispositivo conectado
if ! adb devices | grep -q "device$"; then
    notify-send "scrcpy" "Nenhum dispositivo Android encontrado via USB"
    exit 1
fi

# Espelha a tela
scrcpy --turn-screen-off --stay-awake --fullscreen --no-audio

# Ao sair, religa a tela do celular
adb shell input keyevent KEYCODE_WAKEUP
