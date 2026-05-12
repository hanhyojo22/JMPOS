# Role-Based Features Documentation

## Overview
The POS app now includes comprehensive role-based access control with two user roles: **Admin** and **Staff**.

## User Roles

### Admin
- Full access to all features
- Can create and manage staff accounts
- Can view reports and analytics
- Can reset staff passwords
- Can edit staff information
- Can delete staff accounts

### Staff
- Limited access to core POS operations
- Can view inventory
- Can add products to sales
- Can process sales transactions
- Cannot access admin-only features
- Cannot manage other users

## Features Implemented

### 1. Role-Based Navigation
The bottom navigation bar dynamically shows/hides menu items based on user role:

**For All Users:**
- Home
- Inventory
- Add Products
- Sales

**Admin Only:**
- Reports (for business analytics)
- Staff Management (for user administration)

### 2. Role Display in AppBar
The application header now displays the current user's role with color coding:
- **Admin**: Red badge
- **Staff**: Blue badge

### 3. Staff Management Interface (Admin Only)

#### Features:
- **View all staff members**: See all non-admin users with their details
- **Create new staff**: Add new staff members with username, password, full name, and email
- **Edit staff details**: Update staff member's full name and email
- **Reset password**: Reset a staff member's password (admin can set any password)
- **Delete staff**: Remove a staff member from the system

#### Staff Management Page Components:
- **List View**: Shows all staff with their avatar, name, username, and email
- **Popup Menu**: Quick actions for edit, reset password, and delete
- **Add Dialog**: Form to create new staff members
- **Edit Dialog**: Form to update staff information
- **Reset Password Dialog**: Secure password reset functionality

### 4. Database Methods

New methods added to `DatabaseHelper` class:

```dart
// Create a new staff member
Future<int> createStaff({
  required String username,
  required String password,
  required String fullName,
  required String email,
})

// Get all staff members
Future<List<Map<String, dynamic>>> getAllStaff()

// Get all users (including admins)
Future<List<Map<String, dynamic>>> getAllUsers()

// Delete a staff member
Future<bool> deleteStaff(int userId)

// Update staff information
Future<bool> updateStaff({
  required int userId,
  required String fullName,
  required String email,
})

// Reset staff password
Future<bool> resetStaffPassword({
  required int userId,
  required String newPassword,
})
```

## Default Admin Account

- **Username**: `admin`
- **Password**: `jmsolution123`
- **Full Name**: Juan dela Cruz
- **Email**: admin@posapp.com

## User Data Structure

Users are stored in the `users` table with the following fields:

```
id (INTEGER PRIMARY KEY)
username (TEXT UNIQUE)
password_hash (TEXT) - SHA256 hashed
full_name (TEXT)
email (TEXT)
role (TEXT) - 'admin' or 'staff'
created_at (TEXT) - ISO 8601 timestamp
```

## Security Considerations

1. **Password Hashing**: All passwords are hashed using SHA256 before storage
2. **Role-Based Access**: UI elements are conditionally rendered based on role
3. **Admin Privileges**: Staff management is restricted to admin-only interface
4. **Unique Usernames**: Username uniqueness is enforced at the database level

## How to Use Staff Management

### Creating a Staff Member (Admin Only):
1. Navigate to the **Staff** tab in the navigation bar (admin only)
2. Click the **+** floating action button
3. Fill in the form with:
   - Full Name
   - Username (must be unique)
   - Email (valid email format)
   - Password (minimum 6 characters)
4. Click **Create**

### Editing Staff (Admin Only):
1. Go to **Staff** tab
2. Click the menu icon (⋮) on a staff member's card
3. Select **Edit**
4. Update full name and/or email
5. Click **Update**

### Resetting Staff Password (Admin Only):
1. Go to **Staff** tab
2. Click the menu icon (⋮) on a staff member's card
3. Select **Reset Password**
4. Enter the new password (minimum 6 characters)
5. Click **Reset**

### Deleting Staff (Admin Only):
1. Go to **Staff** tab
2. Click the menu icon (⋮) on a staff member's card
3. Select **Delete**
4. Confirm the deletion

## Role-Based UI Behavior

### Navigation Restrictions
- Staff users only see: Home, Inventory, Add Products, Sales
- Admin users see all tabs: Home, Inventory, Add Products, Sales, Reports, Staff

### Page Content
- When a staff user navigates to Reports (if somehow accessed), they see Sales instead
- When a staff user accesses an admin-only tab, it falls back to appropriate alternative

### Visual Indicators
- Role badge in app header shows current user's role
- Color-coded (Red for Admin, Blue for Staff)

## Files Modified/Created

### Created Files:
- `lib/pages/staff_management.dart` - Staff management interface and dialogs

### Modified Files:
- `lib/database/database_helper.dart` - Added staff management database methods
- `lib/pages/home.dart` - Integrated role-based navigation and UI
- `lib/pages/login.dart` - Passes user role to HomePage

## Future Enhancements

Potential features for future development:
- Role-based activity logging
- Custom role creation
- Permission granularity beyond admin/staff
- Audit logs for staff management actions
- Email notifications for staff creation
- Two-factor authentication
- Session management and logout tracking
