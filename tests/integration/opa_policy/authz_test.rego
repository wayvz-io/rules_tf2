package authz

# Test admin is always allowed
test_admin_allowed if {
	allow with input as {"user": "admin", "action": "write"}
}

# Test admin can delete
test_admin_can_delete if {
	allow with input as {"user": "admin", "action": "delete"}
}

# Test authenticated user can read
test_authenticated_user_can_read if {
	allow with input as {"user": "alice", "authenticated": true, "action": "read"}
}

# Test unauthenticated user cannot read (directly)
test_unauthenticated_cannot_read if {
	not allow with input as {"user": "alice", "authenticated": false, "action": "read"}
}

# Test user can read own resources
test_user_can_read_own_resource if {
	allow with input as {"user": "bob", "resource_owner": "bob", "action": "read"}
}

# Test user cannot read others' resources without auth
test_user_cannot_read_others_resource if {
	not allow with input as {"user": "bob", "resource_owner": "alice", "action": "read", "authenticated": false}
}

# Test suspended user is denied
test_suspended_user_denied if {
	deny with input as {"user": "admin", "user_status": "suspended"}
}

# Test authorized check combines allow and deny
test_authorized_for_normal_admin if {
	authorized with input as {"user": "admin", "user_status": "active"}
}

# Test guest without any permissions is denied
test_guest_denied if {
	not allow with input as {"user": "guest", "action": "read", "authenticated": false}
}
