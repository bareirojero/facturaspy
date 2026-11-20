# Pendientes

## Para la próxima sesión

1. **Respaldo de datos**
   - Ajustes → "Exportar copia de seguridad": un `.zip` con la base de datos, las fotos y el nombre/RUC del titular (sin la API key). Se comparte con el menú de Android (Drive, WhatsApp, mail).
   - Ajustes → "Restaurar copia de seguridad": elegir el `.zip` y reemplazar los datos actuales, con confirmación.
   - Opcional: al generar el PDF del mes, ofrecer guardar una copia.

2. **Pantalla de bienvenida** (solo la primera vez que se abre la app)
   - Qué hace la app.
   - Conectar Gemini: botón a Google AI Studio, campo para pegar la key y prueba automática.
   - Nombre y RUC del titular.
   - Consejos: escanear varias seguidas, borrar deslizando o con pulsación larga, resumen anual, respaldo mensual.

3. **Categoría automática** (hoy siempre queda en "Combustible", la primera de la lista)
   - Pedirle a Gemini la categoría en la misma lectura de la factura, eligiendo solo entre las categorías de la app.
   - Si ya hay facturas confirmadas del mismo proveedor (mismo RUC), usar la categoría que el usuario les puso la última vez; tiene prioridad sobre Gemini.
   - El usuario la puede seguir cambiando en la revisión.
