package authz

# Default deny all access
default allow := false

# Allow admin users to do anything
allow if {
	input.user == "admin"
}

# Allow authenticated users to read
allow if {
	input.action == "read"
	input.authenticated == true
}

# Allow users to access their own resources
allow if {
	input.action == "read"
	input.resource_owner == input.user
}

# Deny access to suspended users
deny if {
	input.user_status == "suspended"
}

# Final decision: allow unless explicitly denied
authorized := allow if {
	not deny
}
