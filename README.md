The problem:
You are running stuff (terraform resources) in a cloud environment backed by a terraform state. Other people in your team are sharing the same resources, a.k.a.: Same `state` file. If you need to change some stuff, other developers won't like it (no pun intended).

The solution:
The idea behind it is to abstract away a set of Terraform resources so while testing stuff locally (during development) we don't mess up the infra that is already being used by someone else. 
This helper will create a `local.backend` file pointing to a **hardcoded bucket** existing in your Cloud (S3). Create it beforehand or run `local-tf help` to see what's needed. 


How to:

Tip: Create an alias in your `~/.zshrc` to make your life easier, like such:

```
alias local-tf="make -f your-local-path/local-tf/Makefile"
```

Now, for every `local-tf` command you run from a repository, will use this sh.

The target terraform resources applied against will be the ones listed in the `local-tf-resources.json` file. You can also use a wildcard -- See the `local-tf-resources.json.sample` file.

For example, running:

```
local-tf init
```

from /user/abc/repo-X/

will effectively run:

```
terraform init -backend-config=environments/staging.tfvars
```

You can run `local-tf help` to see how to use it and the needed files.