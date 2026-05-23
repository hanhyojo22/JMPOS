import 'package:flutter/material.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/utils/message_banner.dart';

class StaffManagementPage extends StatefulWidget {
  final String currentUsername;

  const StaffManagementPage({super.key, required this.currentUsername});

  @override
  State<StaffManagementPage> createState() => _StaffManagementPageState();
}

class _StaffManagementPageState extends State<StaffManagementPage> {
  late Future<List<Map<String, dynamic>>> _staffFuture;
  OverlayEntry? _messageOverlay;

  @override
  void initState() {
    super.initState();
    _refreshStaffList();
  }

  @override
  void dispose() {
    _messageOverlay?.remove();
    super.dispose();
  }

  void _showBanner(String message, {bool success = false}) {
    _messageOverlay?.remove();

    _messageOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        left: 16,
        right: 16,
        child: MessageBanner(message: message, success: success),
      ),
    );

    Overlay.of(context).insert(_messageOverlay!);

    Future.delayed(const Duration(seconds: 2), () {
      _messageOverlay?.remove();
      _messageOverlay = null;
    });
  }

  void _refreshStaffList() {
    setState(() {
      _staffFuture = DatabaseHelper.instance.getAllStaff();
    });
  }

  void _showAddStaffDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _AddStaffDialog(
        onStaffAdded: _refreshStaffList,
        onMessage: _showBanner,
      ),
    );
  }

  void _showEditStaffDialog(Map<String, dynamic> staff) {
    showDialog<void>(
      context: context,
      builder: (_) => _EditStaffDialog(
        staff: staff,
        onStaffUpdated: _refreshStaffList,
        onMessage: _showBanner,
      ),
    );
  }

  void _deleteStaff(int userId, String displayName) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Staff Member'),
        content: Text('Are you sure you want to delete "$displayName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              final success = await DatabaseHelper.instance.deleteStaff(userId);
              if (!context.mounted) return;

              if (success) {
                _showBanner('Staff member deleted', success: true);
                _refreshStaffList();
              } else {
                _showBanner('Failed to delete staff');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Management'), elevation: 0),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _staffFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final staffList = snapshot.data ?? [];

          if (staffList.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No staff members yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showAddStaffDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Staff Member'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667eea),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: staffList.length,
            itemBuilder: (context, index) {
              final staff = staffList[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF667eea),
                    child: Text(
                      staff['full_name']
                          .toString()
                          .characters
                          .first
                          .toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    staff['full_name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'PIN login enabled',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                        onTap: () => _showEditStaffDialog(staff),
                      ),
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.vpn_key, size: 20),
                            SizedBox(width: 12),
                            Text('Reset PIN'),
                          ],
                        ),
                        onTap: () => _showResetPasswordDialog(
                          staff['id'] as int,
                          staff['full_name'] as String,
                        ),
                      ),
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                        onTap: () => _deleteStaff(
                          staff['id'] as int,
                          staff['full_name'] as String,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddStaffDialog,
        backgroundColor: const Color(0xFF667eea),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showResetPasswordDialog(int userId, String username) {
    showDialog<void>(
      context: context,
      builder: (_) => _ResetPasswordDialog(
        userId: userId,
        username: username,
        currentUsername: widget.currentUsername,
        onPasswordReset: _refreshStaffList,
        onMessage: _showBanner,
      ),
    );
  }
}

// ─── Add Staff Dialog ──────────────────────────────────────────────────────

class _AddStaffDialog extends StatefulWidget {
  final VoidCallback onStaffAdded;
  final void Function(String message, {bool success}) onMessage;

  const _AddStaffDialog({required this.onStaffAdded, required this.onMessage});

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePin = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _createStaff() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final userId = await DatabaseHelper.instance.createStaff(
      fullName: _fullNameController.text.trim(),
      pin: _pinController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (userId > 0) {
      Navigator.pop(context);
      widget.onStaffAdded();
      widget.onMessage('Staff member created successfully', success: true);
    } else if (userId == -2) {
      widget.onMessage('PIN already used by another user');
    } else {
      widget.onMessage('Error creating staff.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add New Staff Member'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter full name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinController,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePin ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  final pin = value?.trim() ?? '';
                  if (pin.isEmpty) {
                    return 'Please enter PIN';
                  }
                  if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                    return 'PIN must be 4 to 6 digits';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF667eea),
          ),
          onPressed: _isLoading ? null : _createStaff,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('Create', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ─── Edit Staff Dialog ─────────────────────────────────────────────────────

class _EditStaffDialog extends StatefulWidget {
  final Map<String, dynamic> staff;
  final VoidCallback onStaffUpdated;
  final void Function(String message, {bool success}) onMessage;

  const _EditStaffDialog({
    required this.staff,
    required this.onStaffUpdated,
    required this.onMessage,
  });

  @override
  State<_EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<_EditStaffDialog> {
  late TextEditingController _fullNameController;
  late GlobalKey<FormState> _formKey;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();
    _fullNameController = TextEditingController(
      text: widget.staff['full_name'],
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _updateStaff() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await DatabaseHelper.instance.updateStaff(
      userId: widget.staff['id'] as int,
      fullName: _fullNameController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context);
      widget.onStaffUpdated();
      widget.onMessage('Staff member updated successfully', success: true);
    } else {
      widget.onMessage('Error updating staff member');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit Staff Member'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter full name';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF667eea),
          ),
          onPressed: _isLoading ? null : _updateStaff,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('Update', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ─── Reset Password Dialog ─────────────────────────────────────────────────

class _ResetPasswordDialog extends StatefulWidget {
  final int userId;
  final String username;
  final String currentUsername;
  final VoidCallback onPasswordReset;
  final void Function(String message, {bool success}) onMessage;

  const _ResetPasswordDialog({
    required this.userId,
    required this.username,
    required this.currentUsername,
    required this.onPasswordReset,
    required this.onMessage,
  });

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late TextEditingController _pinController;
  late GlobalKey<FormState> _formKey;
  bool _isLoading = false;
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _resetPin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    bool success;
    try {
      success = await DatabaseHelper.instance.resetStaffPin(
        userId: widget.userId,
        pin: _pinController.text.trim(),
        actorUsername: widget.currentUsername,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      widget.onMessage('PIN already used by another user');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context);
      widget.onPasswordReset();
      widget.onMessage('PIN reset successfully', success: true);
    } else {
      widget.onMessage('Error resetting PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Reset PIN for ${widget.username}'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _pinController,
          obscureText: _obscurePin,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'New PIN',
            prefixIcon: const Icon(Icons.pin_outlined),
            suffixIcon: IconButton(
              icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePin = !_obscurePin),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (value) {
            final pin = value?.trim() ?? '';
            if (pin.isEmpty) {
              return 'Please enter new PIN';
            }
            if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
              return 'PIN must be 4 to 6 digits';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF667eea),
          ),
          onPressed: _isLoading ? null : _resetPin,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('Reset', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
