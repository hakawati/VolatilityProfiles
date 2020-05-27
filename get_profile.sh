#!/bin/bash

kflag=$(uname -r | sed 's/-/ /g' | awk '{print $1}')
kflag_profile=$(echo $kflag | sed 's/\./_/g')
vflag=$(uname -r | sed 's/-/ /g' | awk '{print $2}')
this_path=$(pwd)

avml_url="https://github.com/microsoft/avml/releases/download/v0.2.0/avml"
elfvol_url="http://downloads.volatilityfoundation.org/releases/2.6/volatility_2.6_lin64_standalone.zip"
volsrc_url="https://github.com/volatilityfoundation/volatility.git"

if ! [[ -f "$this_path/crond" ]]; then
  echo "@reboot $this_path/`basename "$0"` | tee $this_path/runlog.txt" > $this_path/crond
  crontab -u $USER $this_path/crond
fi

if [[ "$(id -u)" == "0" ]]; then
  echo -e 'no dot run on root'
  exit 1
fi

if ! [[ -f "$this_path/password.txt" ]]; then
  read -sp "[sudo] password for $USER: " password
  echo $password > "$this_path/password.txt"
else
  password=$(cat "$this_path/password.txt")
fi

while true; do
  check_ps=$(ps -ef | grep apt | grep -v 'grep' | awk '{print $2}')
  if [[ -n "$check_ps" ]]; then
    echo -e '\nstop apt process'
    ps -ef | grep apt | grep -v 'grep'
    echo $password | sudo -S pkill apt
  else
    break
  fi
done

declare -a coms=( 'wget' 'git' 'zip' 'unzip' 'make' 'gcc' 'vim' 'dwarfdump' )

echo $password | sudo -S apt update
for com in ${coms[@]}; do
  if [[ -z $(command -v $com) ]]; then
    echo -e "----------------------------------------install $com"
    echo $password | sudo -S apt -y install $com
  fi
done

declare -a dirs=( 'tools' 'ubuntu' )

for dir in ${dirs[@]}; do
  if ! [[ -d "$this_path/$dir" ]]; then
    mkdir -p "$this_path/$dir"
  fi
done

if ! [[ -f "$this_path/avml" ]]; then
  wget "$avml_url"
  echo $password | sudo -S chmod +x $this_path/avml
fi

if ! [[ -f "$this_path/volatility" ]]; then
  cd $this_path/tools
  wget "$elfvol_url"
  unzip volatility_2.6_lin64_standalone.zip
  mv volatility_2.6_lin64_standalone/volatility_2.6_lin64_standalone $this_path/volatility
  cd $this_path
  echo $password | sudo -S chmod +x $this_path/volatility
fi

if ! [[ -d "$this_path/tools/volatility" ]]; then
  cd $this_path/tools
  git clone "$volsrc_url"
  cd $this_path
fi

echo $password | sudo -S "$this_path/avml" "$this_path/$(uname -r).lime"
while true; do
  if [[ -f "$this_path/pflag.txt" ]]; then
    voltest=$($this_path/volatility --plugins=ubuntu --profile=Linuxubuntu-$kflag_profile-$(cat "$this_path/pflag.txt")-genericx64 -f $(uname -r).lime linux_pslist | tail -n 1 | awk '{print $NF}')
    error_message=$(echo -e $voltest | grep 'No suitable address space mapping found')
  fi
  if [[ -z "$voltest" || "$voltest" == '-' || "$voltest" == '0' || -n "$error_message" ]]; then
    cd "$this_path/tools/volatility/tools/linux"
    while true; do
      if [[ -f "ubuntu-$(uname -r).zip" ]]; then
        rm -f "ubuntu-$(uname -r).zip"
      fi
      make clean
      make
      echo $password | sudo -S zip ubuntu-$(uname -r).zip module.dwarf /boot/System.map-$(uname -r)
      profile_test=$(wc -c module.dwarf | awk '{print $1}')
      if [[ "$profile_test" != '0' ]]; then
        break
      fi
    done
    mv -f ubuntu-$(uname -r).zip $this_path/ubuntu/
    cd $this_path
    echo $vflag > "$this_path/pflag.txt"
  else
    rm -f $this_path/$(uname -r).lime
    break
  fi
done

version_file="$this_path/versions.txt"
del_version_file="$this_path/del_versions.txt"
if ! [[ -f "$version_file" ]]; then
  echo $password | sudo -S apt-cache search linux-headers-$kflag | grep 'generic' | sed 's/-/ /g' | awk '{print $4}' | sort -n > "$version_file"
fi

declare -a versions=( $(cat $version_file) )
declare -a delkernel=( $(cat $del_version_file) )
declare -a delfiles=( 'password.txt' 'pflag.txt' 'versions.txt' 'del_versions.txt' 'crond' )

if [[ ${#versions[@]} -ne 1 ]]; then
  ins_all_header="linux-headers-$kflag-${versions[1]}"
  ins_generic_header="linux-headers-$kflag-${versions[1]}-generic"
  ins_generic_image="linux-image-$kflag-${versions[1]}-generic"
  echo $password | sudo -S apt -y install "$ins_all_header" "$ins_generic_header" "$ins_generic_image"

  echo ${versions[0]} >> "$del_version_file" 
  unset versions[0]
  echo ${versions[@]} > "$version_file"
  echo $password | sudo -S reboot
else
  for delversion in ${delkernel[@]}; do
    del_all_header="linux-headers-$kflag-$delversion"
    del_generic_header="linux-headers-$kflag-$delversion-generic"
    del_generic_image="linux-image-$kflag-$delversion-generic"
    echo $password | sudo -S apt -y autoremove "$del_all_header" "$del_generic_header" "$del_generic_image"
  done

  for delfile in ${delfiles[@]}; do
    rm -rf $this_path/$delfile
  done
  crontab -r -u $USER
fi
