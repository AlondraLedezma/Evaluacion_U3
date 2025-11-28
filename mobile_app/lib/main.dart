import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:flutter/foundation.dart' show kIsWeb; 

// --- CONFIGURACIÓN ---

const String baseUrl = 'http://192.168.0.8:8000'; 

void main() => runApp(MaterialApp(
  debugShowCheckedModeBanner: false,
  home: const LoginScreen(),
  theme: ThemeData(primarySwatch: Colors.indigo),
));

// --- PANTALLA LOGIN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController userCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> login() async {
    setState(() => _isLoading = true);
    try {
      var url = Uri.parse('$baseUrl/login');
      var response = await http.post(url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"username": userCtrl.text, "password": passCtrl.text}));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        Navigator.pushReplacement(context, 
            MaterialPageRoute(builder: (_) => ListaPaquetes(agenteId: data['user_id'])));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Credenciales incorrectas")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error de conexión: $e")));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Paquexpress Login")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center( 
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400), 
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_shipping, size: 100, color: Colors.indigo),
                const SizedBox(height: 20),
                TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "Usuario", icon: Icon(Icons.person))),
                TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Contraseña", icon: Icon(Icons.lock))),
                const SizedBox(height: 30),
                _isLoading 
                  ? const CircularProgressIndicator() 
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                      ),
                      onPressed: login, 
                      child: const Text("INGRESAR")
                    )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- PANTALLA LISTA PAQUETES ---
class ListaPaquetes extends StatefulWidget {
  final int agenteId;
  const ListaPaquetes({super.key, required this.agenteId});
  @override
  _ListaPaquetesState createState() => _ListaPaquetesState();
}

class _ListaPaquetesState extends State<ListaPaquetes> {
  List paquetes = [];

  @override
  void initState() {
    super.initState();
    obtenerPaquetes();
  }

  Future<void> obtenerPaquetes() async {
    try {
      var url = Uri.parse('$baseUrl/paquetes/${widget.agenteId}');
      var response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          paquetes = jsonDecode(response.body);
        });
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Envíos Pendientes"), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: obtenerPaquetes)
      ]),
      body: paquetes.isEmpty 
        ? const Center(child: Text("No hay paquetes pendientes")) 
        : ListView.builder(
          itemCount: paquetes.length,
          itemBuilder: (ctx, i) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2, color: Colors.indigo),
                    title: Text("Paquete #${paquetes[i]['id']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(paquetes[i]['direccion']),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () async {
                      await Navigator.push(context, 
                        MaterialPageRoute(builder: (_) => DetalleEntrega(paquete: paquetes[i])));
                      obtenerPaquetes(); 
                    },
                  ),
                ),
              ),
            );
          },
        ),
    );
  }
}

// --- PANTALLA DETALLE Y ENTREGA ---
class DetalleEntrega extends StatefulWidget {
  final dynamic paquete;
  const DetalleEntrega({super.key, required this.paquete});
  @override
  _DetalleEntregaState createState() => _DetalleEntregaState();
}

class _DetalleEntregaState extends State<DetalleEntrega> {
  XFile? _image; 
  final picker = ImagePicker();
  Position? _currentPosition;
  bool _enviando = false;

  // 1. Obtener GPS
  Future<void> _obtenerGPS() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ubicación obtenida con éxito")));
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error GPS: $e")));
    }
  }

  // --- 2. NUEVO: MENÚ PARA ELEGIR FOTO O GALERÍA ---
  void _mostrarOpcionesFoto() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Container(
            child: Wrap(
              children: <Widget>[
                ListTile(
                    leading: const Icon(Icons.camera_alt, color: Colors.indigo),
                    title: const Text('Tomar Foto con Cámara'),
                    onTap: () {
                      _procesarImagen(ImageSource.camera);
                      Navigator.of(context).pop();
                    }),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Colors.purple),
                  title: const Text('Subir Archivo / Galería'),
                  onTap: () {
                    _procesarImagen(ImageSource.gallery);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  // Función interna para procesar la selección
  Future<void> _procesarImagen(ImageSource origen) async {
    try {
      final pickedFile = await picker.pickImage(source: origen, imageQuality: 50);
      if (pickedFile != null) {
        setState(() {
          _image = pickedFile;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo cargar la imagen")));
    }
  }
  // ----------------------------------------------------

  // 3. Abrir Mapa
  Future<void> _abrirMapa() async {
    final query = Uri.encodeComponent(widget.paquete['direccion']);
    final url = Uri.parse("https://www.google.com/maps/search/?api=1&query=$query");
    
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo abrir el mapa")));
    }
  }

  // 4. Enviar a API
  Future<void> _registrarEntrega() async {
    if (_image == null || _currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Debes tomar foto y obtener GPS")));
      return;
    }

    setState(() => _enviando = true);
    
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/entregar'));
      request.fields['id_paquete'] = widget.paquete['id'].toString();
      request.fields['latitud'] = _currentPosition!.latitude.toString();
      request.fields['longitud'] = _currentPosition!.longitude.toString();

      if (kIsWeb) {
        var bytes = await _image!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('foto', bytes, filename: 'evidencia_web.jpg'));
      } else {
        request.files.add(await http.MultipartFile.fromPath('foto', _image!.path));
      }

      var res = await request.send();
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ ¡Entrega Registrada!")));
        Navigator.pop(context); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error en servidor")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error de conexión: $e")));
    }
    setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Detalle Entrega")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600), 
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Dirección de Entrega:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text("${widget.paquete['direccion']}", style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  
                  ElevatedButton.icon(
                    icon: const Icon(Icons.map),
                    label: const Text("Ver Ruta en Mapa"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[50], foregroundColor: Colors.indigo),
                    onPressed: _abrirMapa,
                  ),
                  const SizedBox(height: 20),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                       ElevatedButton.icon(
                        icon: const Icon(Icons.location_on),
                        label: Text(_currentPosition == null ? "Obtener GPS" : "GPS OK"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _currentPosition == null ? Colors.blue : Colors.green
                        ),
                        onPressed: _obtenerGPS,
                      ),
                      // --- BOTÓN FOTO QUE ABRE EL MENÚ ---
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: Text(_image == null ? "Elegir Foto" : "Foto Lista"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _image == null ? Colors.grey : Colors.orange
                        ),
                        onPressed: _mostrarOpcionesFoto, // <- Ahora llama al menú
                      ),
                      // -----------------------------------
                    ],
                  ),
                  
                  if (_image != null) 
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20), 
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 200,
                          child: kIsWeb 
                            ? Image.network(_image!.path, fit: BoxFit.cover)
                            : Image.file(File(_image!.path), fit: BoxFit.cover),
                        ),
                      )
                    ),

                  const SizedBox(height: 30),
                  
                  _enviando 
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, 
                      padding: const EdgeInsets.all(15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                    onPressed: _registrarEntrega,
                    child: const Text("FINALIZAR ENTREGA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),

                  // --- CUADRO DE UBICACIÓN Y DIRECCIÓN ---
                  if (_currentPosition != null)
                    Container(
                      margin: const EdgeInsets.only(top: 20),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200)
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.satellite_alt, color: Colors.green[700]),
                              const SizedBox(width: 10),
                              Text("Ubicación Detectada", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
                            ],
                          ),
                          const Divider(),
                          Text(
                            "📍 ${widget.paquete['direccion']}", 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 5),
                          Text("Latitud: ${_currentPosition!.latitude.toStringAsFixed(6)}"),
                          Text("Longitud: ${_currentPosition!.longitude.toStringAsFixed(6)}"),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}