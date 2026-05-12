# Role-Based Access Control - Quick Start Guide

## 🚀 Getting Started

### Login as Admin
To access staff management and all admin features:
- **Username**: `admin`
- **Password**: `jmsolution123`

### What You See When Logged In

#### As Admin:
```
Navigation Menu:
├── Home (Dashboard)
├── Inventory (View/Manage Products)
├── Add Products (Add New Items)
├── Sales (Process Transactions)
├── Reports (View Analytics) ← Admin Only
└── Staff (Manage Team) ← Admin Only
```

#### As Staff:
```
Navigation Menu:
├── Home (Dashboard)
├── Inventory (View Products)
├── Add Products (Add New Items)
└── Sales (Process Transactions)
```

## 👥 Managing Staff

### 1️⃣ Creating a Staff Member
1. Login as **admin**
2. Tap the **Staff** tab at the bottom
3. Tap the **+** button
4. Fill in:
   - **Full Name**: Employee name
   - **Username**: Unique login username
   - **Email**: Valid email address
   - **Password**: Minimum 6 characters
5. Tap **Create**

**Example:**
- Full Name: Maria Santos
- Username: maria.santos
- Email: maria@posapp.com
- Password: postaff123

### 2️⃣ Editing Staff Information
1. Go to **Staff** tab
2. Find the staff member
3. Tap the menu (⋮) on their card
4. Select **Edit**
5. Update name or email
6. Tap **Update**

### 3️⃣ Resetting Staff Password
1. Go to **Staff** tab
2. Find the staff member
3. Tap the menu (⋮) on their card
4. Select **Reset Password**
5. Enter new password
6. Tap **Reset**

### 4️⃣ Deleting Staff
1. Go to **Staff** tab
2. Find the staff member
3. Tap the menu (⋮) on their card
4. Select **Delete**
5. Confirm deletion

## 🔐 Security Features

- ✅ All passwords are encrypted (SHA256)
- ✅ Unique usernames prevent duplicates
- ✅ Role-based access prevents unauthorized access
- ✅ Staff cannot access admin-only pages
- ✅ Username/password validation enforced

## 📋 Role Comparison

| Feature | Admin | Staff |
|---------|-------|-------|
| View Home Dashboard | ✅ | ✅ |
| View Inventory | ✅ | ✅ |
| Add Products | ✅ | ✅ |
| Process Sales | ✅ | ✅ |
| View Reports | ✅ | ❌ |
| Create Staff | ✅ | ❌ |
| Edit Staff | ✅ | ❌ |
| Delete Staff | ✅ | ❌ |
| Reset Passwords | ✅ | ❌ |
| Change Own Password | ✅ | ✅ |

## 🎨 Visual Indicators

### Role Badge in Header
- **Red badge "ADMIN"** - You're logged in as an admin
- **Blue badge "STAFF"** - You're logged in as a staff member

## 💡 Common Scenarios

### Scenario 1: New Employee Onboarding
1. Admin creates staff account with temporary password
2. Staff logs in with credentials
3. Staff changes password in Account settings
4. Staff can now process sales

### Scenario 2: Staff Termination
1. Admin goes to Staff tab
2. Finds departing employee
3. Taps menu → Delete
4. Confirms - employee access is revoked

### Scenario 3: Password Reset
1. Employee forgets password
2. Admin goes to Staff tab
3. Finds employee record
4. Taps menu → Reset Password
5. Admin sets temporary password and informs employee
6. Employee can change it on next login

### Scenario 4: Update Employee Email
1. Admin goes to Staff tab
2. Finds employee
3. Taps menu → Edit
4. Updates email address
5. Taps Update

## 🔧 Technical Details

### File Structure
```
lib/
├── pages/
│   ├── home.dart (Updated with role-based navigation)
│   ├── login.dart (Updated to pass role)
│   ├── staff_management.dart (New - Admin only)
│   └── account_page.dart (Shows user role)
├── database/
│   └── database_helper.dart (Added staff management methods)
```

### Database Schema
```
users table:
- id: Primary key
- username: Unique identifier
- password_hash: Encrypted password
- full_name: User's name
- email: User's email
- role: 'admin' or 'staff'
- created_at: Account creation timestamp
```

## ⚠️ Important Notes

1. **Admin Account**: Only one admin account exists by default (admin)
2. **Role Assignment**: Staff created through the UI are always assigned 'staff' role
3. **No Self-Deletion**: Admins cannot delete their own account through the UI
4. **Unique Usernames**: System prevents duplicate usernames
5. **Email Validation**: Email must be in valid format (example@domain.com)

## 🆘 Troubleshooting

### Staff member can't login
- Check username is correct (case-insensitive)
- Verify password is correct
- Admin can reset password if forgotten

### Can't see Staff tab
- Confirm you're logged in as admin
- Check role badge in header shows "ADMIN"

### Creating staff fails
- Ensure username is unique
- Username must be at least 3 characters
- Email must be valid format
- Password must be at least 6 characters

### Staff can't access a feature
- This is expected if it's admin-only (Reports, Staff)
- Staff role has intentional restrictions

## 📞 Support

For issues or questions about the role-based system, refer to:
- `ROLE_BASED_FEATURES.md` - Detailed technical documentation
- `DatabaseHelper` class - Database methods documentation
- `StaffManagementPage` class - UI implementation details
