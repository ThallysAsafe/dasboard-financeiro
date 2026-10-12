const statusText = document.getElementById('statusText');
const alertMessage = document.getElementById('alertMessage');

// Mesmo cuidado da redefinição de senha: tira o token da URL assim que o lê.
const token = new URLSearchParams(window.location.search).get('token');
window.history.replaceState(null, '', window.location.pathname);

function showResult(kind, message, title) {
    statusText.textContent = title;
    alertMessage.textContent = message;
    alertMessage.className = `alert-message alert-${kind}`;
    alertMessage.style.display = 'block';
}

// Confirmar muda dados, então é um POST feito aqui, e não o GET do link: antivírus e
// pré-visualizadores de e-mail abrem links sozinhos e "confirmariam" sem a pessoa.
async function confirmEmail() {
    if (!token) {
        showResult('error', 'Link inválido. Peça um novo no painel.', 'Não foi possível confirmar');
        return;
    }

    try {
        const response = await fetch('/api/v1/auth/email/confirm', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token })
        });
        const data = await response.json();

        if (response.ok) {
            showResult('success', data.message, 'Tudo certo!');
        } else {
            showResult('error', data.error || 'Não foi possível confirmar.', 'Não foi possível confirmar');
        }
    } catch (error) {
        console.error('Erro na requisição:', error);
        showResult('error', 'Erro ao conectar ao servidor. Tente novamente.', 'Não foi possível confirmar');
    }
}

confirmEmail().finally(() => {
    // Sinal de que o resultado já está na tela (ver login.js).
    document.body.dataset.ready = 'true';
});
