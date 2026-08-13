# Guía: buscador de VitaSync con Elasticsearch

Esta guía documenta cómo pasar el buscador del sitio (Práctica 3-4: "aplique
un buscador dentro de su sitio web... realizando pruebas básicas para
encontrar contenido dentro del sitio sin necesidad de salir de este") de su
modo de demostración (FlexSearch en memoria, sin backend) a un buscador real
respaldado por Elasticsearch.

## 1. Por qué dos modos

`vitasync-frontend/src/app/services/search.service.ts` tiene una bandera:

```ts
private readonly MODO_LOCAL = true;
```

- **`MODO_LOCAL = true`** (por defecto): la búsqueda se resuelve con
  [FlexSearch](https://github.com/nextapps-de/flexsearch), un índice
  invertido que corre en el propio navegador. Sirve para desarrollar y
  presentar el sitio sin depender de que Elasticsearch esté levantado.
- **`MODO_LOCAL = false`**: la búsqueda llama a `GET /api/search?q=...` en
  `vitasync-backend`, que consulta un índice real de Elasticsearch.

Ambos modos indexan **el mismo contenido** (ver `search-index.ts` en el
frontend y `SearchIndexSeeder.java` en el backend), así que los resultados
que ve el usuario son consistentes sin importar cuál esté activo.

## 2. Levantar Elasticsearch

Desde `vitasync-backend/`:

```bash
docker compose up -d
```

Esto levanta:

- **Elasticsearch** en `http://localhost:9200` (nodo único, sin seguridad —
  válido para desarrollo local; nunca lo expongas así a internet).
- **Kibana** en `http://localhost:5601` (opcional, útil para explorar el
  índice `vitasync-content` visualmente en *Discover*).

Verifica que Elasticsearch responde:

```bash
curl http://localhost:9200
```

Deberías ver un JSON con `"cluster_name": "docker-cluster"` y la versión.

## 3. Indexar el contenido

No hace falta ningún paso manual: al arrancar el backend
(`mvn spring-boot:run`), la clase `SearchIndexSeeder` revisa si el índice
`vitasync-content` está vacío y, si lo está, carga las ~18 entradas
(Inicio, Nosotros, Contacto, FAQ) que hoy viven en `search-index.ts`. En
reinicios posteriores no vuelve a duplicar los documentos.

Para forzar una re-siembra (por ejemplo, tras cambiar el contenido),
borra el índice y reinicia el backend:

```bash
curl -X DELETE http://localhost:9200/vitasync-content
```

## 4. Probar el endpoint directamente

```bash
curl "http://localhost:8081/api/search?q=sueño"
curl "http://localhost:8081/api/search?q=smartwach"   # con error de tecleo: fuzziness AUTO lo tolera
```

La respuesta usa exactamente los mismos campos que `ResultadoBusqueda` en
Angular (`id`, `titulo`, `contenido`, `ruta`, `fragmento`, `categoria`), así
que no se necesita ningún mapeo adicional en el frontend.

## 5. Activar el modo real en Angular

Edita `vitasync-frontend/src/app/services/search.service.ts`:

```ts
private readonly MODO_LOCAL = false;
```

Corre `ng serve` con el backend y Elasticsearch activos. El cuadro de
búsqueda del navbar ahora resuelve contra `/api/search`.

## 6. Cómo funciona la relevancia

`SearchService.buscar()` usa una consulta `multi_match` sobre `titulo`
(con boost x2, para que coincidencias en el título pesen más) y
`contenido`, con `fuzziness: AUTO` para tolerar errores de tecleo — el
mismo comportamiento aproximado que el `tokenize: 'forward'` de FlexSearch
en el modo local, pero resuelto por el motor de búsqueda real en vez de en
el navegador.

## 7. Problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `curl http://localhost:9200` no responde | Docker Desktop no está corriendo, o el contenedor sigue arrancando | `docker compose ps`, espera al healthcheck o revisa `docker compose logs elasticsearch` |
| El backend falla al arrancar por Elasticsearch | El contenedor no estaba levantado antes de `mvn spring-boot:run` | Levanta primero `docker compose up -d`, confirma con `curl :9200`, luego corre el backend |
| `GET /api/search` devuelve `[]` siempre | El índice no se sembró (por ejemplo, se corrió el backend antes de que Elasticsearch estuviera listo) | Revisa el log de arranque (`SearchIndexSeeder`), o borra el índice (paso 3) y reinicia |
| Error de compatibilidad de versión del cliente | La imagen de Elasticsearch en `docker-compose.yml` es muy distinta a la que gestiona Spring Boot | Ajusta el tag de la imagen en `docker-compose.yml` a una versión 8.x cercana a la que trae `spring-boot-starter-data-elasticsearch` |
| En Windows, Docker se queda sin memoria | Elasticsearch por defecto pide bastante RAM | Ya se limita con `ES_JAVA_OPTS=-Xms512m -Xmx512m` en `docker-compose.yml`; si sigue fallando, sube el límite de memoria de Docker Desktop |
