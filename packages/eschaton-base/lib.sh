#!/usr/bin/env bash
# Fonctions pures du socle Eschaton. Sourcé par eschaton-update/-rollback.

check_free_space_kb() { # $1=dispo_kb $2=minimum_kb
  [[ "$1" -ge "$2" ]]
}

running_kernel_missing_modules() { # $1=/usr/lib/modules $2=$(uname -r)
  [[ ! -d "$1/$2" ]]
}
