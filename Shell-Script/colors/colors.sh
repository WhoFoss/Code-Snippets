#!/usr/bin/env bash
#####################################################################
#---------------------------------------------------------------#
# Autor: WhoFoss
# script: colors.sh
# DESCRIÇÃO: Imprime texto colorido no terminal usando marcações
#            como @red, @green, @b e @u, com escopo em [[...]].
# Dependências: bash, sed, tput (ncurses-bin)
# Recursos: cores (@red @green @yellow @blue @magenta @cyan @white),
#           negrito (@b), sublinhado (@u) e reset (@reset)
# Exemplo: colorir "@red@b[[Texto em vermelho e negrito]] normal"
#---------------------------------------------------------------#
#####################################################################


#####################################################################
#---------------------------------------------------------------#
# FUNÇÕES
#---------------------------------------------------------------#
#####################################################################

# Converte as marcações @cor/@b/@u em sequências de escape do terminal
colors() {
    echo "$@" | sed \
        -e "s/\(\(@\(red\|green\|yellow\|blue\|magenta\|cyan\|white\|reset\|b\|u\)\)\+\)[[]\{2\}\(.*\)[]]\{2\}/\1\4@reset/g" \
        -e "s/@red/$(tput setaf 1)/g" \
        -e "s/@green/$(tput setaf 2)/g" \
        -e "s/@yellow/$(tput setaf 3)/g" \
        -e "s/@blue/$(tput setaf 4)/g" \
        -e "s/@magenta/$(tput setaf 5)/g" \
        -e "s/@cyan/$(tput setaf 6)/g" \
        -e "s/@white/$(tput setaf 7)/g" \
        -e "s/@reset/$(tput sgr0)/g" \
        -e "s/@b/$(tput bold)/g" \
        -e "s/@u/$(tput sgr 0 1)/g"
}
