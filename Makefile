LOCAL_TF := bash $(dir $(abspath $(lastword $(MAKEFILE_LIST))))local-tf.sh

.PHONY: help init plan apply destroy output

help:
	@$(LOCAL_TF) help

init:
	@$(LOCAL_TF) init

plan:
	@$(LOCAL_TF) plan

apply:
	@$(LOCAL_TF) apply

destroy:
	@$(LOCAL_TF) destroy

output:
	@$(LOCAL_TF) output
