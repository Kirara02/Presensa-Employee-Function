import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart' as models;

Future<dynamic> main(final dynamic context) async {
  final payload =
      jsonDecode(context.req.bodyRaw.isEmpty ? '{}' : context.req.bodyRaw)
          as Map<String, dynamic>;
  final action = payload['action'] as String?;

  if (action == null) {
    return context.res.json({'success': false, 'error': 'Action is required.'},
        statusCode: 400);
  }

  try {
    final client = Client()
        .setEndpoint(Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT']!)
        .setProject(Platform.environment['APPWRITE_FUNCTION_PROJECT_ID']!)
        .setKey(Platform.environment['APPWRITE_API_KEY']!);

    final users = Users(client);
    final tables = TablesDB(client);

    final databaseId = Platform.environment['APPWRITE_DB_ID']!;
    final usersTableId = 'users';

    switch (action) {
      case 'list':
        context.log('Action: List Employees');

        final results = await Future.wait([
          tables.listRows(databaseId: databaseId, tableId: usersTableId),
          users.list(),
        ]);

        final userRows = results[0] as models.RowList;
        final authUsers = results[1] as models.UserList;
        final authUsersMap = {for (var u in authUsers.users) u.$id: u};

        final List<Map<String, dynamic>> combinedList = [];
        for (var row in userRows.rows) {
          final rowData = row.data;
          final authUser = authUsersMap[rowData['userId']];

          if (authUser != null) {
            combinedList.add({
              'userId': rowData['userId'],
              'documentId': row.$id,
              'name': authUser.name,
              'email': authUser.email,
              'role': rowData['role'],
              'department': rowData['department'],
              'phone': rowData['phone'],
              'company': rowData['companyId'],
              'shift': rowData['shiftId'],
            });
          }
        }
        return context.res.json({'success': true, 'data': combinedList});

      case 'getById':
        context.log('Action: Get Employee By ID');
        final String rowId = payload['documentId'];

        final row = await tables.getRow(
          databaseId: databaseId,
          tableId: usersTableId,
          rowId: rowId,
        );
        final rowData = row.data;

        final authUser = await users.get(userId: rowData['userId']);

        final Map<String, dynamic> combinedData = {
          'userId': rowData['userId'],
          'documentId': row.$id,
          'name': authUser.name,
          'email': authUser.email,
          'role': rowData['role'],
          'department': rowData['department'],
          'phone': rowData['phone'],
          'company': rowData['companyId'],
          'shift': rowData['shiftId'],
        };
        return context.res.json({'success': true, 'data': combinedData});

      case 'update':
        context.log('Action: Update Employee');
        final Map<String, dynamic> employeeData = payload['employeeData'];
        final String userId = employeeData['userId'];

        final currentUser = await users.get(userId: userId);
        if (currentUser.name != employeeData['name']) {
          await users.updateName(userId: userId, name: employeeData['name']);
        }
        if (currentUser.email != employeeData['email']) {
          await users.updateEmail(userId: userId, email: employeeData['email']);
        }

        await tables.updateRow(
          databaseId: databaseId,
          tableId: usersTableId,
          rowId: employeeData['documentId'],
          data: {
            'role': employeeData['role'],
            'department': employeeData['department'],
            'phone': employeeData['phone'],
            'shiftId': employeeData['shiftId'],
          },
        );
        return context.res.json(
            {'success': true, 'message': 'Employee updated successfully'});

      case 'create':
        context.log('Action: Create Employee');
        final newUser = await users.create(
          userId: ID.unique(),
          email: payload['email'],
          password: payload['password'],
          name: payload['name'],
        );
        await users.updateEmailVerification(
          userId: newUser.$id,
          emailVerification: true,
        );

        await tables.createRow(
          databaseId: databaseId,
          tableId: usersTableId,
          rowId: ID.unique(),
          data: {
            'userId': newUser.$id,
            'role': payload['role'],
            'department': payload['department'],
            'phone': payload['phone'],
            'companyId': payload['companyId'],
            'shiftId': payload['shiftId'],
          },
        );
        return context.res.json({
          'success': true,
          'message': 'Employee created successfully.',
          'userId': newUser.$id
        });

      case 'delete':
        context.log('Action: Delete Employee');
        final String userId = payload['userId'];
        final String rowId = payload['documentId'];
        await Future.wait([
          users.delete(userId: userId),
          tables.deleteRow(
            databaseId: databaseId,
            tableId: usersTableId,
            rowId: rowId,
          ),
        ]);
        return context.res.json(
            {'success': true, 'message': 'Employee deleted successfully.'});

      default:
        throw Exception('Invalid action: $action');
    }
  } catch (e, st) {
    context.error('An error occurred: $e\n$st');
    return context.res.json({'success': false, 'error': e.toString()});
  }
}
