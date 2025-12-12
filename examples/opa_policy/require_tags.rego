package terraform.tags

# Required tags that must be present on all taggable resources
required_tags := {"Environment", "Owner", "Project"}

# Default deny
default allow := false

# Allow if all taggable resources have required tags
allow if {
	count(violation_resources) == 0
}

# Find all violations - resources missing required tags
violation_resources contains resource if {
	some resource in input.resource_changes
	resource.change.actions[_] != "delete"
	is_taggable_resource(resource.type)
	missing := missing_tags(resource)
	count(missing) > 0
}

# Check if resource type supports tags
is_taggable_resource(type) if {
	taggable_types := {
		"aws_instance",
		"aws_s3_bucket",
		"aws_vpc",
		"aws_subnet",
		"aws_security_group",
		"aws_rds_instance",
		"aws_lambda_function",
	}
	type in taggable_types
}

# Find missing tags for a resource
missing_tags(resource) := missing if {
	tags := object.get(resource.change.after, "tags", {})
	tags_all := object.get(resource.change.after, "tags_all", tags)
	present := {tag | tags_all[tag]}
	missing := required_tags - present
}

# Get all violation messages
violation_messages contains msg if {
	some resource in violation_resources
	missing := missing_tags(resource)
	msg := sprintf("%s '%s' is missing required tags: %v", [resource.type, resource.address, missing])
}
