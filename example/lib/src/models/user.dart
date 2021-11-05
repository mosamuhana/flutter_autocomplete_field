class User {
  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final DateTime birthDate;

  String get name => '$firstName $lastName';

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.birthDate,
  });

  @override
  String toString() {
    return 'User (id: $id, name: $name, email: $email, birthDate: $birthDate)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.birthDate == birthDate;
  }

  @override
  int get hashCode {
    return id.hashCode ^ name.hashCode ^ email.hashCode ^ birthDate.hashCode;
  }
}
