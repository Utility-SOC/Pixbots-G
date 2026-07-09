git filter-branch -f --env-filter '
if [ "$GIT_AUTHOR_NAME" = "Natalia Garrido" ] || [ "$GIT_AUTHOR_NAME" = "nataliangarrido" ]; then
    export GIT_AUTHOR_NAME="utility-soc"
    export GIT_AUTHOR_EMAIL="utility-soc@users.noreply.github.com"
fi
if [ "$GIT_COMMITTER_NAME" = "Natalia Garrido" ] || [ "$GIT_COMMITTER_NAME" = "nataliangarrido" ]; then
    export GIT_COMMITTER_NAME="utility-soc"
    export GIT_COMMITTER_EMAIL="utility-soc@users.noreply.github.com"
fi
' HEAD
