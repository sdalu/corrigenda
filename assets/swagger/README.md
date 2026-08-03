# Swagger UI, vendored

Two files out of [swagger-ui-dist](https://www.npmjs.com/package/swagger-ui-dist)
5.32.12, Apache-2.0 (`LICENSE`, and `swagger-ui-bundle.js.LICENSE.txt`
for what it bundles):

    swagger-ui-bundle.js    1.5 MB
    swagger-ui.css          179 KB

They are here rather than on a CDN because every framework on this
estate is self-hosted, and because the page they are used by sits
behind a login: a viewer that fetches a megabyte and a half from
somebody else's server on every visit is a third party watching an
authenticated page.

Nothing builds them. To move to another release:

    npm pack swagger-ui-dist@<version>
    tar xzf swagger-ui-dist-<version>.tgz \
        package/swagger-ui-bundle.js package/swagger-ui.css \
        package/LICENSE package/swagger-ui-bundle.js.LICENSE.txt
    cp package/* assets/swagger/

then open `/apidocs` and see that the schema still renders. The page
that uses them is `views/apidocs.erb`; it takes the standalone bundle,
not the preset one, because the topbar and its URL box are exactly what
a viewer of one fixed schema does not want.
