cmd_Module.symvers :=  sed 's/ko$$/o/'  modules.order | scripts/mod/modpost      -o Module.symvers -n -T - vmlinux.o
