# Odoo - Holding La Labranza

Repositorio privado para personalizaciones exclusivas de Holding La Labranza.
Cada módulo instalable debe vivir directamente bajo `addons/` y tener un nombre
con el prefijo `holdinglalabranza_`.

```text
addons/
  holdinglalabranza_<funcionalidad>/
    __manifest__.py
    models/
    views/
    security/
    static/
```

La base transversal de Poliedro se mantiene en su propio repositorio; no la
copies aquí. Tampoco incluyas Odoo Community, Enterprise, módulos comprados,
datos del cliente, respaldos, contraseñas ni certificados. La pipeline copia
solo los módulos de este repositorio a `/opt/poliedro-odoo/src/custom-addons/`
en el Droplet de staging y crea un backup de `odoo_dev` antes de desplegar.

Los `push` a `main` publican el código y reinician Odoo, pero no actualizan el
esquema de la base. Para instalar o actualizar módulos, ejecuta manualmente la
acción **Deploy Holding La Labranza addons to staging** e indica los nombres
completos en `install_modules` o `update_modules`.

El flujo despliega solo addons cuyos nombres empiecen por
`holdinglalabranza_`. No elimina automáticamente módulos retirados: esa
limpieza puede afectar datos y se debe planear aparte.
