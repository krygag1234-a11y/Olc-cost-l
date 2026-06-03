#!/usr/bin/env bash
# Auto SWAP detection and creation for VPS with low RAM

[[ -n "${_OLC_SWAP_LOADED:-}" ]] && return 0
_OLC_SWAP_LOADED=1

# Check if swap is needed (RAM < 4GB and no swap active)
olc_swap_check() {
  local ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
  local swap_mb=$(free -m | awk '/^Swap:/ {print $2}')
  
  [[ "$ram_mb" -lt 4096 && "$swap_mb" -eq 0 ]]
}

# Calculate recommended swap size
olc_swap_recommend() {
  local ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
  local swap_size_mb
  
  if [[ "$ram_mb" -lt 2048 ]]; then
    swap_size_mb=$((ram_mb * 2))  # 2x RAM if < 2GB
  elif [[ "$ram_mb" -lt 4096 ]]; then
    swap_size_mb=$ram_mb          # 1x RAM if 2-4GB
  else
    swap_size_mb=2048             # 2GB if > 4GB
  fi
  
  echo "$swap_size_mb"
}

# Create swap file
olc_swap_create() {
  local size_mb="${1:-2048}"
  local swapfile="${2:-/swapfile}"
  
  [[ -f "$swapfile" ]] && { echo "Swap file already exists: $swapfile"; return 1; }
  
  echo "Creating ${size_mb}MB swap at $swapfile..."
  
  # Check available disk space
  local avail_mb=$(df -Pm / | awk 'NR==2 {print $4}')
  if [[ "$avail_mb" -lt "$((size_mb + 500))" ]]; then
    echo "ERROR: Not enough disk space (need ${size_mb}MB, have ${avail_mb}MB)"
    return 1
  fi
  
  # Create swap
  dd if=/dev/zero of="$swapfile" bs=1M count="$size_mb" status=progress || return 1
  chmod 600 "$swapfile"
  mkswap "$swapfile" || return 1
  swapon "$swapfile" || return 1
  
  # Make persistent
  if ! grep -q "$swapfile" /etc/fstab; then
    echo "$swapfile none swap sw 0 0" >> /etc/fstab
  fi
  
  echo "Swap created and activated: ${size_mb}MB"
  free -h
  return 0
}

