import 'package:flutter/material.dart';
import 'package:autocomplete_field/autocomplete_field.dart';

import '../models/user.dart';
import '../services/user.service.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoComplete Field Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: AutoCompleteField<User>(
          decoration: const InputDecoration(labelText: 'Search'),
          delegate: onSearch,
          //itemExtent: 50,
          itemBuilder: (context, entry) {
            return ListTile(
              title: Text(entry.name),
              subtitle: Text(entry.email),
            );
          },
          onItemSelected: (entry) {
            print(entry.name);
          },
        ),
      ),
    );
  }

  Future<List<User>> onSearch(String query) async {
    print('[onSearch] query: $query');
    try {
      final res = await UserService().search(query);
      return res;
    } catch (e) {
      return [];
    }
  }
}
