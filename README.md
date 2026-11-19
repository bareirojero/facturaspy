# Facturas PY — Guía Completa de Instalación, Compilación y Uso

Aplicación Android personal en Flutter para registrar facturas de gastos en Paraguay mediante extracción automática con **Google Gemini**, almacenamiento local en SQLite y exportación de reportes mensuales en PDF para el contador.

---

## 1. Estructura de archivos incluida

```text
facturas_py/
├── .github/workflows/
│   └── build.yml                     # CI/CD en GitHub Actions (genera APK release en cada push a main)
├── android/app/src/main/
│   └── AndroidManifest.xml           # Permisos de Cámara, Internet y Galería
├── lib/
│   ├── db/
│   │   └── database_helper.dart      # Base de datos SQLite ("facturas") y respaldo local de fotos
│   ├── models/
│   │   └── factura.dart              # Modelo de datos y categorías por defecto
│   ├── screens/
│   │   ├── ajustes_screen.dart       # Configuración segura de API Key, modelo y datos del titular
│   │   ├── factura_form_screen.dart  # Formulario editable con validación de montos y zoom de imagen
│   │   ├── home_screen.dart          # Listado mensual, totales de IVA y exportación a PDF
│   │   └── procesando_screen.dart    # Pantalla de carga mientras Gemini analiza la factura
│   ├── services/
│   │   ├── gemini_service.dart       # Redimensionamiento (1600px, JPEG 85) y llamada REST a Gemini
│   │   ├── pdf_service.dart          # Generador de PDF mensual (tabla horizontal + páginas con fotos)
│   │   └── settings_service.dart     # Almacenamiento cifrado (flutter_secure_storage)
│   ├── utils/
│   │   └── formatters.dart           # Formato de guaraníes (separador de miles con punto) y fechas
│   ├── widgets/
│   │   └── imagen_zoom_dialog.dart   # Visor de pantalla completa con pellizco/zoom
│   └── main.dart                     # Punto de entrada Material 3 y localización es_PY
├── pubspec.yaml                      # Dependencias con versiones fijadas
└── README.md                         # Esta guía
```

---

## 2. Compilar localmente

El repositorio ya incluye la base Android generada por `flutter create` (minSdk 23).

```bash
flutter pub get
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

---

## 3. Compilación automática en GitHub Actions (sin instalar Android Studio)

1. Cada vez que hagas `push` a la rama `main`, GitHub Actions compilará automáticamente el APK release.
2. Entrá a la pestaña **Actions** de tu repositorio, abrí la última ejecución exitosa y descargá el artifact **`facturas-py-apk`**.

---

## 4. Cómo obtener la API Key de Google Gemini (Gratis)

1. Ingresá a **[Google AI Studio](https://aistudio.google.com/)** con tu cuenta de Google.
2. En el menú lateral izquierdo, hacé clic en **Get API key**.
3. Presioná **Create API key** (podés crearla en un proyecto nuevo o existente).
4. Copiá la clave generada (empieza con `AIzaSy...`).

---

## 5. Configuración inicial dentro de la App

1. Abrí **Facturas PY** en tu teléfono.
2. Tocá el ícono de **Ajustes** (arriba a la derecha).
3. Pegá tu **API Key de Gemini** (se guarda cifrada en el dispositivo mediante `flutter_secure_storage`).
4. Dejá el modelo por defecto (`gemini-flash-latest`) o escribí otro modelo multimodal compatible (ej. `gemini-2.5-flash`).
5. Tocá **Probar conexión** para verificar que la clave funcione.
6. Completá tu **Nombre / Razón Social** y **RUC** (estos datos encabezarán el PDF mensual para tu contador).
7. Tocá **Guardar Ajustes**.

---

## 6. Flujo de uso diario y exportación mensual

- **Cargar factura**: Tocá el botón **`+`** abajo a la derecha -> elegí **Sacar foto** o **Galería**. La app redimensiona la imagen a 1600 px (JPEG 85), consulta a Gemini y precarga fecha, RUC, razón social, timbrado, número de factura, condición, gravadas (10% y 5%), exenta, IVA (10% y 5%) y total.
- **Validación automática**: Si `gravada_10 + gravada_5 + exenta` difiere del `total` en más de 1 Gs., se muestra una advertencia amarilla sin impedir guardar. Si no tenés internet o falla la API, podés cargar los datos a mano.
- **Editar / Eliminar**: Tocá cualquier factura de la lista para editarla o amplía su foto tocando la miniatura. Deslizá hacia la izquierda para eliminarla con confirmación.
- **Exportar PDF para el contador**: Seleccioná el mes/año en la barra superior y tocá el ícono de **PDF** en la barra superior. Se generará `facturas_YYYY_MM.pdf` con:
  1. Tabla resumen horizontal con todos los comprobantes y fila de totales.
  2. Cuadro de subtotales por categoría.
  3. Una página individual por cada factura con sus datos fiscales y la fotografía respaldatoria escalada.
  4. Diálogo nativo para compartir directo por WhatsApp, correo o Drive.
