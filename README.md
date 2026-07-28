
Terraform [workspaces](https://developer.hashicorp.com/terraform/cloud-docs/workspaces) already solve this very same problem. Therefore, this repo has been archived.

The problem:
You are running stuff (terraform resources) in a cloud environment backed by a terraform state. Other people in your team are sharing the same resources, a.k.a.: Same `state` file. If you need to change some stuff, other developers won't like it.

The solution:
The idea behind it is to abstract away a set of Terraform resources so while testing stuff locally (during development) we don't mess up the infra that is already being used by someone else. 
This helper will create a `local.backend` file pointing to a **configurable bucket** existing in your Cloud (S3). You must create the bucket beforehand. 


How to:

Create an alias in your `~/.zshrc` to make your life easier, like such:

```
alias local-tf="make -f your-local-path/local-tf/Makefile"
```

Add the 2 following ENV variables to your `~/.zshrc`. Replace its value to fit your own setup .They will be referenced by your `local-tf` commands.
```
export PERSONAL_TF_WORKSPACE_BUCKET="someone-workspace"
export WORKSPACE_TFVARS_FILE="staging.tfvars"
```

Now, you can run a `local-tf` command from a repository. You must declare the resources you want to point to in the `local-tf-resources.json` file at the root of your target repository. Then, the target Terraform resources applied against will be the ones listed there.   
You can also use a wildcard to reference a whole module -- See the `local-tf-resources.json.sample` file.


Run `local-tf help` to get started with it.


For example, running `local-tf init` from `/user/abc/my-special-repo/` will effectively run the following command — backed by **your own tfstate file** in the bucket you configured:

```
terraform init -backend-config=environments/staging.tfvars
```

You can run `local-tf help` to see how to use it and the needed files.
