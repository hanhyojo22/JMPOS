# Visual Reference: Role-Based Features

## 🎨 UI Components Overview

### AppBar with Role Badge
```
┌─────────────────────────────────────────────────┐
│ Good morning!  [ADMIN]        👤              │
├─────────────────────────────────────────────────┤
│           POS Dashboard Content                │
└─────────────────────────────────────────────────┘
```

**For Staff Member:**
```
┌─────────────────────────────────────────────────┐
│ Good afternoon!  [STAFF]      👤              │
├─────────────────────────────────────────────────┤
│           POS Dashboard Content                │
└─────────────────────────────────────────────────┘
```

### Bottom Navigation Bar

**Admin View (6 items):**
```
┌─────────────────────────────────────────────────┐
│ 🏠 Home │📦 Inventory │➕ Add │📊 Sales │    │
│                                    📈 Reports │
│                                    👥 Staff  │
└─────────────────────────────────────────────────┘
```

**Staff View (4 items):**
```
┌─────────────────────────────────────────────────┐
│ 🏠 Home │📦 Inventory │➕ Add │📊 Sales │
└─────────────────────────────────────────────────┘
```

### Staff Management Page Layout

#### When Staff List is Empty:
```
┌──────────────────────────────────────────┐
│  Staff Management                    ✕  │
├──────────────────────────────────────────┤
│                                          │
│              👥                          │
│        No staff members yet              │
│                                          │
│      ┌──────────────────────────┐       │
│      │  + Add First Staff      │       │
│      │     Member              │       │
│      └──────────────────────────┘       │
│                                          │
│                      ⊕                   │
│                      +                   │
└──────────────────────────────────────────┘
```

#### When Staff Members Exist:
```
┌──────────────────────────────────────────┐
│  Staff Management                    ✕  │
├──────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ 📊 Maria Santos              ⋮     │ │
│  │    @maria.santos                   │ │
│  │    maria@posapp.com                │ │
│  └────────────────────────────────────┘ │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ 🅹 John Smith                ⋮     │ │
│  │    @john.smith                     │ │
│  │    john@posapp.com                 │ │
│  └────────────────────────────────────┘ │
│                                          │
│                      ⊕                   │
│                      +                   │
└──────────────────────────────────────────┘
```

### Popup Menu (Staff Card)
```
Staff Member Card
    ↓
⋮ (Menu Button)
    ↓
┌──────────────────────┐
│ ✏️  Edit            │
│ 🔑 Reset Password   │
│ 🗑️  Delete          │
└──────────────────────┘
```

### Add Staff Dialog
```
┌─────────────────────────────────────┐
│ Add New Staff Member            ✕ │
├─────────────────────────────────────┤
│                                     │
│ Full Name: ___________________     │
│                                     │
│ Username:  ___________________     │
│                                     │
│ Email:     ___________________     │
│                                     │
│ Password:  ___________________  👁 │
│                                     │
│       [Cancel]      [Create]        │
└─────────────────────────────────────┘
```

### Edit Staff Dialog
```
┌─────────────────────────────────────┐
│ Edit Staff Member               ✕ │
├─────────────────────────────────────┤
│                                     │
│ Full Name: ___________________     │
│                                     │
│ Email:     ___________________     │
│                                     │
│       [Cancel]      [Update]        │
└─────────────────────────────────────┘
```

### Reset Password Dialog
```
┌─────────────────────────────────────┐
│ Reset Password for maria.santos ✕ │
├─────────────────────────────────────┤
│                                     │
│ New Password: _________________  👁 │
│                                     │
│       [Cancel]      [Reset]         │
└─────────────────────────────────────┘
```

### Delete Confirmation Dialog
```
┌─────────────────────────────────────┐
│ Delete Staff Member             ✕ │
├─────────────────────────────────────┤
│ Are you sure you want to delete    │
│ "maria.santos"?                    │
│                                     │
│       [Cancel]      [Delete]        │
└─────────────────────────────────────┘
```

## 🔄 Navigation Flows

### Admin Complete Flow
```
LOGIN
  │
  ├─→ Home (ADMIN)
  │     ├─→ Dashboard
  │     └─→ Back to Menu
  │
  ├─→ Inventory
  │     ├─→ View Products
  │     └─→ Back to Menu
  │
  ├─→ Add Products
  │     ├─→ Add New Item
  │     └─→ Back to Menu
  │
  ├─→ Sales
  │     ├─→ Process Transaction
  │     └─→ Back to Menu
  │
  ├─→ Reports
  │     ├─→ View Analytics
  │     └─→ Back to Menu
  │
  └─→ Staff Management
        ├─→ View Staff List
        ├─→ Create Staff
        │   ├─→ Fill Form
        │   ├─→ Submit
        │   └─→ Confirm
        ├─→ Edit Staff
        │   ├─→ Update Info
        │   └─→ Save
        ├─→ Reset Password
        │   ├─→ Enter New Password
        │   └─→ Confirm
        └─→ Delete Staff
            ├─→ Confirm
            └─→ Done
```

### Staff Limited Flow
```
LOGIN
  │
  ├─→ Home (STAFF)
  │     ├─→ Dashboard
  │     └─→ Back to Menu
  │
  ├─→ Inventory
  │     ├─→ View Products
  │     └─→ Back to Menu
  │
  ├─→ Add Products
  │     ├─→ Add New Item
  │     └─→ Back to Menu
  │
  └─→ Sales
        ├─→ Process Transaction
        └─→ Back to Menu
```

## 📱 Screen Examples

### Admin Home Screen Header
```
Good morning!  [ADMIN]        👤
Today's Revenue | May 11, 2026
💹
$1,234.56
┌──────────────────────────────────┐
│ 🧾 Transactions: 42              │
│ 📦 Avg. Order: $29.39            │
└──────────────────────────────────┘
```

### Staff Home Screen Header
```
Good afternoon!  [STAFF]       👤
Today's Revenue | May 11, 2026
💹
$1,234.56
┌──────────────────────────────────┐
│ 🧾 Transactions: 42              │
│ 📦 Avg. Order: $29.39            │
└──────────────────────────────────┘
```

## 🎯 Role Badge Styling

### Admin Badge
```
┌──────────┐
│ ADMIN    │  ← Red background with red text
└──────────┘
```
Colors:
- Background: rgba(255, 0, 0, 0.3)
- Text: Colors.red[700]
- Font: Bold, 12pt

### Staff Badge
```
┌──────────┐
│ STAFF    │  ← Blue background with blue text
└──────────┘
```
Colors:
- Background: rgba(0, 0, 255, 0.3)
- Text: Colors.blue[700]
- Font: Bold, 12pt

## 📊 Data Display Examples

### Staff List Item
```
┌─────────────────────────────────────┐
│ 🅼  Maria Santos              ⋮    │
│     @maria.santos                  │
│     maria@posapp.com               │
└─────────────────────────────────────┘
```

Fields:
- Avatar: First letter of full name
- Full Name: Bold, larger text
- Username: Gray, with @ prefix
- Email: Smaller gray text
- Menu: Tap ⋮ for actions

## 🔐 Validation Messages

### Success Scenarios
```
✅ Staff member created successfully
✅ Staff member updated successfully
✅ Password reset successfully
✅ Staff member deleted
```

### Error Scenarios
```
❌ Invalid username or password.
❌ Error creating staff. Username might already exist.
❌ Please enter full name
❌ Please enter a valid email
❌ Password must be at least 6 characters
❌ Username must be at least 3 characters
```

## 🎨 Color Scheme

| Element | Color | Usage |
|---------|-------|-------|
| Admin Button | #667EEA | Primary action, accent |
| Success | Green | Confirmations |
| Error | Red/Red[700] | Errors, deletions |
| Admin Badge | Red[700] | Role indicator |
| Staff Badge | Blue[700] | Role indicator |
| Text Primary | #333333 | Main text |
| Text Secondary | Gray | Descriptions |
| Background | White | Surfaces |
| Gradient | #667EEA → #764BA2 | Headers |

## 📐 Responsive Layout

All components are designed to be responsive:
- Mobile: Full-width, single column
- Tablet: Optimized padding, card layout
- Desktop: Proper scaling maintained

## ✨ Animations

- **Role Badge**: Appears instantly in AppBar
- **Staff List**: Fade-in animation when loading
- **Dialogs**: Slide-up animation from bottom
- **Buttons**: Ripple effect on tap
- **Loading**: Circular progress indicator

## 🎯 Accessibility Features

- Clear color contrast
- Readable font sizes (minimum 12pt)
- Proper icon usage with labels
- Touch targets > 48x48 dp
- Error messages clear and actionable
- Form validation in real-time

---

This visual reference complements the technical documentation and guides. Refer to actual implementation in code for exact colors and dimensions.
