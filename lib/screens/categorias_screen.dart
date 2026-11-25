import 'package:flutter/material.dart';
import '../db/database_helper.dart';

/// Administrar categorías: agregar, renombrar, borrar y ordenar (arrastrando).
class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  final _db = DatabaseHelper.instance;
  List<String>? _categorias;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await _db.getCategorias();
    if (mounted) setState(() => _categorias = lista);
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Diálogo con un campo de texto. Devuelve el texto o null si se cancela.
  Future<String?> _pedirNombre({required String titulo, String inicial = ''}) {
    final ctrl = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _agregar() async {
    final nombre = (await _pedirNombre(titulo: 'Nueva categoría'))?.trim();
    if (nombre == null || nombre.isEmpty) return;
    final ok = await _db.agregarCategoria(nombre);
    if (!ok) {
      _mensaje('Ya existe una categoría "$nombre".');
      return;
    }
    await _cargar();
  }

  Future<void> _renombrar(String viejo) async {
    final nuevo = (await _pedirNombre(titulo: 'Renombrar categoría', inicial: viejo))?.trim();
    if (nuevo == null || nuevo.isEmpty || nuevo == viejo) return;

    final usadas = await _db.contarFacturasDeCategoria(viejo);
    bool actualizar = true;
    if (usadas > 0) {
      if (!mounted) return;
      final r = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Actualizar facturas?'),
          content: Text(
            '$usadas factura(s) tienen la categoría "$viejo". '
            '¿Pasarlas también a "$nuevo"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Dejarlas en "$viejo"'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
      if (r == null) return;
      actualizar = r;
    }

    final ok = await _db.renombrarCategoria(viejo, nuevo, actualizarFacturas: actualizar);
    if (!ok) {
      _mensaje('Ya existe una categoría "$nuevo".');
      return;
    }
    await _cargar();
  }

  Future<void> _borrar(String nombre) async {
    final lista = _categorias ?? [];
    if (lista.length <= 1) {
      _mensaje('Tiene que quedar al menos una categoría.');
      return;
    }
    final usadas = await _db.contarFacturasDeCategoria(nombre);
    if (!mounted) return;

    if (usadas == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Borrar categoría'),
          content: Text('¿Borrar "$nombre"? Ninguna factura la usa.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await _db.borrarCategoria(nombre);
      await _cargar();
      return;
    }

    // En uso: elegir a qué categoría pasan sus facturas.
    final otras = lista.where((c) => c != nombre).toList();
    String destino = otras.contains('Otros') ? 'Otros' : otras.first;
    final elegido = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Borrar categoría'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$usadas factura(s) usan "$nombre". ¿A qué categoría las pasamos?'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: destino,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Pasar a',
                  border: OutlineInputBorder(),
                ),
                items: otras
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setD(() => destino = v ?? destino),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, destino),
              child: const Text('Borrar y pasar'),
            ),
          ],
        ),
      ),
    );
    if (elegido == null) return;
    await _db.borrarCategoria(nombre, moverA: elegido);
    _mensaje('"$nombre" borrada. Sus facturas pasaron a "$elegido".');
    await _cargar();
  }

  Future<void> _reordenar(int viejo, int nuevo) async {
    final lista = List.of(_categorias!);
    if (nuevo > viejo) nuevo -= 1;
    lista.insert(nuevo, lista.removeAt(viejo));
    setState(() => _categorias = lista);
    await _db.reordenarCategorias(lista);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _categorias;
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregar,
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: lista == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Gemini elige la categoría de cada factura entre estas. '
                    'Arrastrá desde el ícono de la derecha para ordenarlas.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    buildDefaultDragHandles: false,
                    itemCount: lista.length,
                    onReorder: _reordenar,
                    itemBuilder: (context, i) {
                      final c = lista[i];
                      return ListTile(
                        key: ValueKey(c),
                        title: Text(c),
                        onTap: () => _renombrar(c),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Renombrar',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _renombrar(c),
                            ),
                            IconButton(
                              tooltip: 'Borrar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _borrar(c),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
