const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'ewer-8f788' });
admin.auth().projectConfigManager().getProjectConfig()
    .then(config => console.log(JSON.stringify(config, null, 2)))
    .catch(err => console.error(err));
