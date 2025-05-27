#!/usr/bin/env sh

(
  git log --author="snyk-bot" --pretty=format:"%H"
  git log --author="dependabot" --pretty=format:"%H"
  git log --author="renovate-bot" --pretty=format:"%H"
  git log --author="renovate" --pretty=format:"%H"
  git log --author="github-actions" --pretty=format:"%H"
) | sort | uniq >.git-blame-ignore-revs

#git add .git-blame-ignore-revs
#git commit -m "Add .git-blame-ignore-revs for bot commits"
#git push
