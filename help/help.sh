#!/bin/bash

#######################################
# Print a help for given script
# Arguments:
#   script name
#######################################

help=$(cat ${BASH_SOURCE%/*}/$1.md)
help=${help//<b>/\\033[1m}
help=${help//<\/b>/\\033[22m}
help=${help//"\`\`\`"/"'"}
help=${help//"\`"/"'"}
help=${help//"==="/""}
help=${help//"=="/""}
echo -e "$help" | less -RFX
