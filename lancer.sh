#!/bin/sh
flatpak run org.godotengine.Godot --path "$(dirname "$0")" "$@"
