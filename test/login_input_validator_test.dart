import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/login_input_validator.dart';

void main() {
  group('LoginInputValidator', () {
    test('sanitizes usernames consistently', () {
      expect(
        LoginInputValidator.sanitizeUsername('  Admin\u0000@Example.COM  '),
        'admin@example.com',
      );
    });

    test('removes control characters from passwords', () {
      expect(
        LoginInputValidator.sanitizePassword('sec\u0000ret\u007F'),
        'secret',
      );
    });

    test('accepts usernames and email addresses used for login', () {
      expect(LoginInputValidator.isValidUsernameOrEmail('admin_1'), isTrue);
      expect(
        LoginInputValidator.isValidUsernameOrEmail('owner@example.com'),
        isTrue,
      );
      expect(LoginInputValidator.isValidUsernameOrEmail('owner-name'), isFalse);
    });

    test('validates password bounds', () {
      expect(LoginInputValidator.isValidPassword('12345'), isFalse);
      expect(LoginInputValidator.isValidPassword('123456'), isTrue);
      expect(
        LoginInputValidator.isValidPassword(
          'a' * (LoginInputValidator.maxPasswordLength + 1),
        ),
        isFalse,
      );
    });
  });
}
