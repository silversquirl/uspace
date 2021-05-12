# Contributing

All changes to uspace, no matter how small, should be committed to a separate
branch. This branch can contain whatever commits you like; for instance, if you
implement a new tool and later fix a bug in it, these can be separate commits.
Once it is ready for merge, this change should be reviewed. Here, changes may be
requested, in which case these changes must be made and the branch must be
re-reviewed.

Once the review passes, the branch is nearly ready to be merged into `main`.
Firstly, however, the commit history should be cleaned up. An interactive rebase
can be used to squash all the commits for a branch together where necessary.
There are some cases where this may not make sense - for instance, a branch
consisting of a mass code style change should likely be split into several
commits, one for each style change. However, if, for instance, a new utility was
implemented, all relevent commits should be rebased into one. In this rebase, a
`Reviewed-by` trailer should be added to all commits (see the 'Commit messages'
section below).

Now, the branch should be rebased onto the latest `main` branch; this prevents
merge commits from filling the history. Finally, `main` shall be fast-forwarded
to this branch, and the branch deleted.

Note that the last few stages (interactive rebase and rebase onto main) can be
performed by a core contributor as part of the merge process for PRs.

## Commit messages

All commits to uspace must follow the [conventional commits] specification, with
the following types of commit:

- `new`: creation of a new utility
- `feat`: adding a feature to an existing utility
- `fix`: bugfix to an existing utility
- `refactor`: non-functional code changes
- `build`: changes to build system, CI etc
- `docs`: changes or additions to documentation

The first character of the commit subject after the type should be lowercase.

A commit's footer may contain the following trailers:
- `Reviewed-by`: contains the reviewer's name and, optionally, email
- `Resolves`: contains the ID of a GitHub issue which is resolved by this commit

[conventional commits]: https://www.conventionalcommits.org/en/v1.0.0/

## Branch names

Branches should be named `type/description`, where `type` matches a commit type
as given above, and `description` is a short description of the change. The name
should be entirely lowercase, and use dashes for word separation if needed.
Branches for adding new utilities should be named `new/name`, where `name` is
the exact name of the utility.
