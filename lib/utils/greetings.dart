import 'package:intl/intl.dart';

class Greetings {
  static String getGreeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good Morning!';
    } else if (hour < 18) {
      return 'Good Afternoon!';
    } else if (hour < 21) {
      return 'Good Evening!';
    } else {
      return 'Good Night!';
    }
  }

  //  Add today's date
  static String getTodayDate() {
    return DateFormat('MMMM d, yyyy').format(DateTime.now());
  }

  //  Optional: Greeting + Date combined
  static String getGreetingWithDate() {
    return '${getGreeting()} Today is ${getTodayDate()}';
  }
}
