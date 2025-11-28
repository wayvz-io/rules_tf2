# Parent Module

This module tests the nested dependency chain:
- Parent uses Child
- Child uses Grandchild
- Parent should NOT need to declare Grandchild in its modules list
