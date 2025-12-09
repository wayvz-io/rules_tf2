package terraform.tags

# Test: Resource with all required tags should pass
test_resource_with_all_tags if {
	allow with input as {"resource_changes": [{
		"type": "aws_instance",
		"address": "aws_instance.web",
		"change": {
			"actions": ["create"],
			"after": {"tags": {
				"Environment": "production",
				"Owner": "platform-team",
				"Project": "web-app",
			}},
		},
	}]}
}

# Test: Resource missing a required tag should fail
test_resource_missing_tag if {
	not allow with input as {"resource_changes": [{
		"type": "aws_instance",
		"address": "aws_instance.web",
		"change": {
			"actions": ["create"],
			"after": {"tags": {
				"Environment": "production",
				"Owner": "platform-team",
			}},
		},
	}]}
}

# Test: Resource with no tags should fail
test_resource_no_tags if {
	not allow with input as {"resource_changes": [{
		"type": "aws_s3_bucket",
		"address": "aws_s3_bucket.data",
		"change": {
			"actions": ["create"],
			"after": {},
		},
	}]}
}

# Test: Delete action should be allowed even without tags
test_delete_action_allowed if {
	allow with input as {"resource_changes": [{
		"type": "aws_instance",
		"address": "aws_instance.old",
		"change": {
			"actions": ["delete"],
			"after": null,
		},
	}]}
}

# Test: Non-taggable resource should be allowed
test_non_taggable_resource_allowed if {
	allow with input as {"resource_changes": [{
		"type": "aws_iam_policy",
		"address": "aws_iam_policy.example",
		"change": {
			"actions": ["create"],
			"after": {},
		},
	}]}
}

# Test: Multiple resources - all compliant
test_multiple_resources_all_compliant if {
	allow with input as {"resource_changes": [
		{
			"type": "aws_instance",
			"address": "aws_instance.web",
			"change": {
				"actions": ["create"],
				"after": {"tags": {
					"Environment": "production",
					"Owner": "team-a",
					"Project": "api",
				}},
			},
		},
		{
			"type": "aws_s3_bucket",
			"address": "aws_s3_bucket.logs",
			"change": {
				"actions": ["create"],
				"after": {"tags_all": {
					"Environment": "production",
					"Owner": "team-a",
					"Project": "api",
				}},
			},
		},
	]}
}

# Test: Mixed resources - one non-compliant should fail
test_mixed_resources_one_fails if {
	not allow with input as {"resource_changes": [
		{
			"type": "aws_instance",
			"address": "aws_instance.web",
			"change": {
				"actions": ["create"],
				"after": {"tags": {
					"Environment": "production",
					"Owner": "team-a",
					"Project": "api",
				}},
			},
		},
		{
			"type": "aws_s3_bucket",
			"address": "aws_s3_bucket.logs",
			"change": {
				"actions": ["create"],
				"after": {"tags": {"Environment": "production"}},
			},
		},
	]}
}

# Test: Empty resource changes should pass
test_empty_resource_changes if {
	allow with input as {"resource_changes": []}
}

# Test: Violation resources are found
test_violation_resources if {
	violations := violation_resources with input as {"resource_changes": [{
		"type": "aws_instance",
		"address": "aws_instance.test",
		"change": {
			"actions": ["create"],
			"after": {"tags": {"Environment": "dev"}},
		},
	}]}
	count(violations) > 0
}
