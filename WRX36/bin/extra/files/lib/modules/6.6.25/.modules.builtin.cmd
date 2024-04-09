savedcmd_modules.builtin := tr '\0' '\n' < modules.builtin.modinfo | sed -n 's/^[[:alnum:]:_]*\.file=//p' | tr ' ' '\n' | uniq | sed -e 's:^:kernel/:' -e 's/$$/.ko/' > modules.builtin
