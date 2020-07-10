#!/bin/bash

if git st | grep -qw 'deleted:' >& /dev/null
then
  git add $(git st | grep -qw 'deleted:' | awk '{print $2}')
fi

git add * 2> /dev/null

git st

if [ $# -eq 0 ]
then
  git ci -m "routine development at $(date)"
else
  git ci -m "$@"
fi

git push || echo "NOTICE: no remote defined, continuing..."