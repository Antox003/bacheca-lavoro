import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const JobBoardApp());
}

// ============================================================================
// SERVIZIO API E GESTIONE CONFIGURAZIONE / SESSIONE
// ============================================================================
class ApiService {
  // INSERISCI QUI L'IP DEL TUO PC COME VALORE PREDEFINITO
  static String serverIp = '192.168.1.100';
  static String serverPort = '8080';

  static Map<String, dynamic>? currentCompany;

  static String get baseUrl => 'http://$serverIp:$serverPort';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    serverIp = prefs.getString('server_ip') ?? serverIp;
    final savedCompany = prefs.getString('current_company');
    if (savedCompany != null) {
      currentCompany = jsonDecode(savedCompany);
    }
  }

  static Future<void> setServerIp(String ip) async {
    serverIp = ip.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', serverIp);
  }

  static Future<void> setSession(Map<String, dynamic> company) async {
    currentCompany = company;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_company', jsonEncode(company));
  }

  static Future<void> logout() async {
    currentCompany = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_company');
  }

  // R1 - Registrazione
  static Future<void> register(String name, String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 201) {
      throw Exception(data['error'] ?? 'Errore durante la registrazione');
    }
  }

  // R2 - Login
  static Future<void> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Credenziali errate');
    }
    await setSession(data['company']);
  }

  // R5 - Lista Annunci
  static Future<List<dynamic>> getJobs() async {
    final res = await http.get(Uri.parse('$baseUrl/api/jobs'));
    if (res.statusCode != 200) {
      throw Exception('Errore nel caricamento degli annunci');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  // R4 - Pubblica Annuncio
  static Future<void> createJob(String title, String description, String location) async {
    if (currentCompany == null) throw Exception('Non autenticato');
    final res = await http.post(
      Uri.parse('$baseUrl/api/jobs'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'companyId': currentCompany!['id'],
        'companyName': currentCompany!['name'],
        'title': title,
        'description': description,
        'location': location,
      }),
    );
    if (res.statusCode != 201) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Errore pubblicazione annuncio');
    }
  }

  // R6 - Candidatura con CV
  static Future<void> applyToJob({
    required String jobId,
    required String firstName,
    required String lastName,
    required String email,
    required File cvFile,
    required String cvFileName,
  }) async {
    final bytes = await cvFile.readAsBytes();
    final base64Cv = base64Encode(bytes);

    final res = await http.post(
      Uri.parse('$baseUrl/api/jobs/$jobId/apply'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'cvBase64': base64Cv,
        'cvFileName': cvFileName,
      }),
    );
    if (res.statusCode != 201) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Errore invio candidatura');
    }
  }

  // R7 - Ottieni candidature di un annuncio
  static Future<List<dynamic>> getApplications(String jobId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/jobs/$jobId/applications'));
    if (res.statusCode != 200) {
      throw Exception('Errore caricamento candidature');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }
}

// ============================================================================
// APP PRINCIPALE
// ============================================================================
class JobBoardApp extends StatelessWidget {
  const JobBoardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JobBoard MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF608BBC)),
        useMaterial3: true,
      ),
      home: const PublicJobBoardScreen(),
    );
  }
}

// ============================================================================
// SCHERMATA 1: BACHECA PUBBLICA ANNUNCI (R5)
// ============================================================================
class PublicJobBoardScreen extends StatefulWidget {
  const PublicJobBoardScreen({super.key});

  @override
  State<PublicJobBoardScreen> createState() => _PublicJobBoardScreenState();
}

class _PublicJobBoardScreenState extends State<PublicJobBoardScreen> {
  late Future<List<dynamic>> _jobsFuture;

  @override
  void initState() {
    super.initState();
    _refreshJobs();
  }

  void _refreshJobs() {
    setState(() {
      _jobsFuture = ApiService.getJobs();
    });
  }

  void _showIpConfigDialog() {
    final controller = TextEditingController(text: ApiService.serverIp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configura IP Server PC'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Indirizzo IPv4 del PC',
            hintText: 'es. 192.168.1.45',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async {
              await ApiService.setServerIp(controller.text);
              if (mounted) {
                Navigator.pop(ctx);
                _refreshJobs();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Server impostato su ${ApiService.baseUrl}')),
                );
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLogged = ApiService.currentCompany != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bacheca Lavoro'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_ethernet),
            tooltip: 'Configura IP Server',
            onPressed: _showIpConfigDialog,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              icon: Icon(isLogged ? Icons.business : Icons.login),
              label: Text(isLogged ? 'Area Azienda' : 'Accesso Aziende'),
              onPressed: () async {
                if (isLogged) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CompanyDashboardScreen()),
                  );
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CompanyAuthScreen()),
                  );
                }
                _refreshJobs();
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshJobs(),
        child: FutureBuilder<List<dynamic>>(
          future: _jobsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(
                        'Impossibile connettersi a ${ApiService.baseUrl}\nAssicurati che il server sia avviato e di aver impostato l\'IP corretto tramite l\'icona in alto.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _refreshJobs, child: const Text('Riprova')),
                    ],
                  ),
                ),
              );
            }

            final jobs = snapshot.data ?? [];
            if (jobs.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Nessun annuncio pubblicato al momento.')),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      job['title'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.business, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(job['companyName'] ?? 'Azienda'),
                            const SizedBox(width: 16),
                            const Icon(Icons.location_on, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(job['location'] ?? ''),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          job['description'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// SCHERMATA 2: DETTAGLIO ANNUNCIO + CANDIDATURA (R5, R6)
// ============================================================================
class JobDetailScreen extends StatelessWidget {
  final Map<String, dynamic> job;
  const JobDetailScreen({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final isCompany = ApiService.currentCompany != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Dettaglio Annuncio')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job['title'],
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Chip(
              avatar: const Icon(Icons.business, size: 18),
              label: Text('${job['companyName']} • ${job['location']}'),
            ),
            const Divider(height: 32),
            const Text(
              'Descrizione della posizione',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(job['description'], style: const TextStyle(fontSize: 15, height: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            if (!isCompany)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Candidati ora', style: TextStyle(fontSize: 16)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ApplyJobScreen(job: job)),
                    );
                  },
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Sei autenticato come Azienda: le aziende non possono candidarsi agli annunci.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SCHERMATA 3: FORM CANDIDATURA CON UPLOAD CV (R6 - Scenario S2)
// ============================================================================
class ApplyJobScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  const ApplyJobScreen({super.key, required this.job});

  @override
  State<ApplyJobScreen> createState() => _ApplyJobScreenState();
}

class _ApplyJobScreenState extends State<ApplyJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  File? _selectedCvFile;
  String? _selectedCvName;
  bool _isSubmitting = false;

  Future<void> _pickCv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );
    if (result != null && result.isNotEmpty && result.single.path != null) {
      setState(() {
        _selectedCvFile = File(result.single.path!);
        _selectedCvName = result.single.name;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCvFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona il file del tuo Curriculum (PDF)')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.applyToJob(
        jobId: widget.job['id'],
        firstName: _firstNameCtrl.text,
        lastName: _lastNameCtrl.text,
        email: _emailCtrl.text,
        cvFile: _selectedCvFile!,
        cvFileName: _selectedCvName!,
      );
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Candidatura Inviata!'),
            content: Text(
              'La tua candidatura per "${widget.job['title']}" è stata registrata con successo.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx); // chiude dialog
                  Navigator.pop(context); // torna al dettaglio
                  Navigator.pop(context); // torna alla bacheca
                },
                child: const Text('Torna alla bacheca'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invia Candidatura')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Posizione: ${widget.job['title']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Inserisci il nome' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameCtrl,
                decoration: const InputDecoration(labelText: 'Cognome', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Inserisci il cognome' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || !v.contains('@') ? 'Inserisci un\'email valida' : null,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _pickCv,
                icon: const Icon(Icons.upload_file),
                label: Text(_selectedCvName ?? 'Allega Curriculum (PDF)'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Conferma Invio Candidatura'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCHERMATA 4: LOGIN E REGISTRAZIONE AZIENDA (R1, R2 - Scenario S1)
// ============================================================================
class CompanyAuthScreen extends StatefulWidget {
  const CompanyAuthScreen({super.key});

  @override
  State<CompanyAuthScreen> createState() => _CompanyAuthScreenState();
}

class _CompanyAuthScreenState extends State<CompanyAuthScreen> {
  bool _isLogin = true;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await ApiService.login(_emailCtrl.text, _passwordCtrl.text);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CompanyDashboardScreen()),
          );
        }
      } else {
        await ApiService.register(_nameCtrl.text, _emailCtrl.text, _passwordCtrl.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account creato! Ora effettua il login.')),
          );
          setState(() => _isLogin = true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Login Azienda' : 'Registrazione Azienda')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Icon(Icons.business_center, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              if (!_isLogin) ...[
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome Azienda',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Aziendale',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || !v.contains('@') ? 'Email non valida' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (v) => v == null || v.length < 4 ? 'Minimo 4 caratteri' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(_isLogin ? 'Accedi' : 'Crea Account'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin
                      ? 'Non hai un account aziendale? Registrati'
                      : 'Hai già un account? Accedi',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCHERMATA 5: AREA RISERVATA AZIENDA (R3, R4, R7 - Scenari S1, S3)
// ============================================================================
class CompanyDashboardScreen extends StatefulWidget {
  const CompanyDashboardScreen({super.key});

  @override
  State<CompanyDashboardScreen> createState() => _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState extends State<CompanyDashboardScreen> {
  late Future<List<dynamic>> _myJobsFuture;

  @override
  void initState() {
    super.initState();
    _loadMyJobs();
  }

  void _loadMyJobs() {
    final companyId = ApiService.currentCompany?['id'];
    setState(() {
      _myJobsFuture = ApiService.getJobs().then(
            (all) => all.where((j) => j['companyId'] == companyId).toList(),
      );
    });
  }

  Future<void> _handleLogout() async {
    await ApiService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PublicJobBoardScreen()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyName = ApiService.currentCompany?['name'] ?? 'Azienda';

    return Scaffold(
      appBar: AppBar(
        title: Text('Area Riservata: $companyName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nuovo Annuncio'),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateJobScreen()),
          );
          _loadMyJobs();
        },
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _myJobsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final jobs = snapshot.data ?? [];
          if (jobs.isEmpty) {
            return const Center(
              child: Text('Non hai ancora pubblicato annunci.\nPremi "+ Nuovo Annuncio" per iniziare.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(job['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(job['location'] ?? ''),
                  trailing: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Candidature'),
                      SizedBox(width: 4),
                      Icon(Icons.people),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => JobApplicationsScreen(job: job)),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// SCHERMATA 6: CREAZIONE ANNUNCIO (R4 - Scenario S1)
// ============================================================================
class CreateJobScreen extends StatefulWidget {
  const CreateJobScreen({super.key});

  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isSaving = false;

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ApiService.createJob(_titleCtrl.text, _descCtrl.text, _locationCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Annuncio pubblicato in bacheca!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pubblica Nuovo Annuncio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titolo posizione (es. Sviluppatore Flutter)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Inserisci il titolo' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sede di lavoro (es. Milano / Remoto)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Descrizione dettagliata e requisiti',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Inserisci la descrizione' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isSaving ? null : _publish,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Pubblica Annuncio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCHERMATA 7: CONSULTAZIONE CANDIDATURE E APERTURA CV (R7 - Scenario S3)
// ============================================================================
class JobApplicationsScreen extends StatelessWidget {
  final Map<String, dynamic> job;
  const JobApplicationsScreen({super.key, required this.job});

  Future<void> _openCv(BuildContext context, String cvRelativeUrl) async {
    try {
      final fileName = cvRelativeUrl.split('/').last;
      final url = Uri.parse('${ApiService.baseUrl}/api/files/$fileName');

      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw Exception('File non trovato sul server (Errore ${response.statusCode})');
      }

      final tempDir = await getTemporaryDirectory();
      final localFile = File('${tempDir.path}/$fileName');
      await localFile.writeAsBytes(response.bodyBytes);

      final result = await OpenFilex.open(localFile.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossibile aprire il file: ${result.message}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore apertura CV: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Candidati: ${job['title']}')),
      body: FutureBuilder<List<dynamic>>(
        future: ApiService.getApplications(job['id']),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final apps = snapshot.data ?? [];
          if (apps.isEmpty) {
            return const Center(child: Text('Nessuna candidatura ricevuta per questo annuncio.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${app['firstName']} ${app['lastName']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text('Email: ${app['email']}'),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.picture_as_pdf),
                        label: Text('Apri CV (${app['cvFileName']})'),
                        onPressed: () => _openCv(context, app['cvUrl']),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}