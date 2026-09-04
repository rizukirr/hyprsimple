#!/bin/bash
dir="$HOME/.config/rofi"
theme='launcher/style'

## Run
rofi \
    -show drun \
    -theme "${dir}/${theme}.rasi"
