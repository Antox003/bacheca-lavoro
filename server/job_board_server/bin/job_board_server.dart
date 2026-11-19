import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

final File dbFile = File('db.json');
final Directory uploadsDir = Directory('uploads');

// Struttura iniziale del database JSON
Map<String, dynamic> db = {
  'companies': [],
  'jobs': [],
  'applications': [],
};

void loadDb() {
  if (!uploadsDir.existsSync()) {
    uploadsDir.createSync(recursive: true);
  }
  if (dbFile.existsSync()) {
    final content = dbFile.readAsStringSync();
    if (content.isNotEmpty) {
      db = jsonDecode(content);
    }
  } else {
    saveDb();
  }
}

void saveDb() {
  const encoder = JsonEncoder.withIndent('  ');
  dbFile.writeAsStringSync(encoder.convert(db));
}

Response jsonResponse(Object body, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}

void main() async {
  loadDb();
  final router = Router();

  // R1 - Registrazione Azienda
  router.post('/api/register', (Request request) async {
    final payload = jsonDecode(await request.readAsString());
    final name = (payload['name'] ?? '').toString().trim();
    final email = (payload['email'] ?? '').toString().trim().toLowerCase();
    final password = (payload['password'] ?? '').toString();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      return jsonResponse({'error': 'Tutti i campi sono obbligatori'}, statusCode: 400);
    }

    final companies = db['companies'] as List;
    if (companies.any((c) => c['email'] == email)) {
      return jsonResponse({'error': 'Email già registrata'}, statusCode: 409);
    }

    final newCompany = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'email': email,
      'password': password,
    };

    companies.add(newCompany);
    saveDb();

    return jsonResponse({
      'message': 'Registrazione completata',
      'company': {
        'id': newCompany['id'],
        'name': newCompany['name'],
        'email': newCompany['email'],
      }
    }, statusCode: 201);
  });

  // R2 - Login Azienda
  router.post('/api/login', (Request request) async {
    final payload = jsonDecode(await request.readAsString());
    final email = (payload['email'] ?? '').toString().trim().toLowerCase();
    final password = (payload['password'] ?? '').toString();

    final companies = db['companies'] as List;
    final company = companies.firstWhere(
          (c) => c['email'] == email && c['password'] == password,
      orElse: () => null,
    );

    if (company == null) {
      return jsonResponse({'error': 'Credenziali non valide'}, statusCode: 401);
    }

    return jsonResponse({
      'message': 'Login effettuato',
      'company': {
        'id': company['id'],
        'name': company['name'],
        'email': company['email'],
      }
    });
  });

// R5 - Elenco Annunci Pubblici
  router.get('/api/jobs', (Request request) {
    final jobs = List.of(db['jobs'] as List);
    jobs.sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));
    return jsonResponse(jobs);
  });

  // R4 - Pubblicazione Nuovo Annuncio (Azienda)
  router.post('/api/jobs', (Request request) async {
    final payload = jsonDecode(await request.readAsString());
    final companyId = (payload['companyId'] ?? '').toString();
    final companyName = (payload['companyName'] ?? '').toString();
    final title = (payload['title'] ?? '').toString().trim();
    final description = (payload['description'] ?? '').toString().trim();
    final location = (payload['location'] ?? 'Remoto / Sede').toString().trim();

    if (companyId.isEmpty || title.isEmpty || description.isEmpty) {
      return jsonResponse({'error': 'Titolo e descrizione obbligatori'}, statusCode: 400);
    }

    final newJob = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'companyId': companyId,
      'companyName': companyName,
      'title': title,
      'description': description,
      'location': location.isEmpty ? 'Non specificata' : location,
      'createdAt': DateTime.now().toIso8601String(),
    };

    (db['jobs'] as List).add(newJob);
    saveDb();

    return jsonResponse(newJob, statusCode: 201);
  });

  // R6 - Invio Candidatura + Upload File CV (Base64)
  router.post('/api/jobs/<jobId>/apply', (Request request, String jobId) async {
    final payload = jsonDecode(await request.readAsString());
    final firstName = (payload['firstName'] ?? '').toString().trim();
    final lastName = (payload['lastName'] ?? '').toString().trim();
    final email = (payload['email'] ?? '').toString().trim();
    final cvBase64 = (payload['cvBase64'] ?? '').toString();
    final originalFileName = (payload['cvFileName'] ?? 'curriculum.pdf').toString();

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || cvBase64.isEmpty) {
      return jsonResponse({'error': 'Tutti i campi e il CV sono obbligatori'}, statusCode: 400);
    }

    // Salva il file fisico nella cartella uploads
    final appId = DateTime.now().millisecondsSinceEpoch.toString();
    final safeFileName = '${appId}_${originalFileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final fileBytes = base64Decode(cvBase64);
    final savedFile = File('${uploadsDir.path}/$safeFileName');
    await savedFile.writeAsBytes(fileBytes);

    final newApplication = {
      'id': appId,
      'jobId': jobId,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'cvFileName': originalFileName,
      'cvUrl': '/uploads/$safeFileName',
      'appliedAt': DateTime.now().toIso8601String(),
    };

    (db['applications'] as List).add(newApplication);
    saveDb();

    return jsonResponse({'message': 'Candidatura inviata con successo'}, statusCode: 201);
  });

  // R7 - Consultazione Candidature per un Annuncio (Azienda)
  router.get('/api/jobs/<jobId>/applications', (Request request, String jobId) {
    final allApps = db['applications'] as List;
    final filtered = allApps.where((a) => a['jobId'] == jobId).toList();
    return jsonResponse(filtered);
  });


  // Rotta diretta per scaricare/visualizzare il CV caricato
  router.get('/api/files/<fileName>', (Request request, String fileName) async {
    final file = File('${uploadsDir.path}/$fileName');
    if (!await file.exists()) {
      return Response.notFound('File non trovato');
    }
    final bytes = await file.readAsBytes();
    final contentType = fileName.toLowerCase().endsWith('.pdf')
        ? 'application/pdf'
        : 'application/octet-stream';

    return Response.ok(
      bytes,
      headers: {
        'Content-Type': contentType,
        'Content-Disposition': 'inline; filename="$fileName"',
      },
    );
  });

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(router.call);

  // InternetAddress.anyIPv4 permette la connessione dallo smartphone sulla stessa rete Wi-Fi
  final server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
  print('Server avviato su http://${server.address.address}:${server.port}');
  print('Database salvato in: ${dbFile.absolute.path}');
}