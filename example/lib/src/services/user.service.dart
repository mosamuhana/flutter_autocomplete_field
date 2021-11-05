import 'dart:math';
import 'package:faker/faker.dart';

import '../models/user.dart';

class UserService {
  static UserService? _instance;
  factory UserService() => _instance ??= UserService._();
  UserService._();

  Future<List<User>> search(String name) async {
    Future.delayed(const Duration(milliseconds: 500));
    if (List.generate(3, (index) => _random.nextBool()).any((x) => x)) {
      final count = 2 + _random.nextInt(10);
      return List.generate(count, (index) => _createUser(name));
    }
    return [];
  }
}

final _faker = Faker();
final _random = Random();

User _createUser(String firstName) {
  final lastName = _faker.person.lastName();
  firstName = firstName[0].toUpperCase() + firstName.substring(1);
  return User(
    id: _faker.guid.random.integer(1000000, min: 1),
    firstName: firstName,
    lastName: lastName,
    email: '$firstName.$lastName@example.com'.toLowerCase(),
    birthDate: _faker.date.dateTime(minYear: 1970, maxYear: 2000),
  );
}
