const form = document.getElementById('forgotForm');
const alertMessage = document.getElementById('alertMessage');
const btnSubmit = document.getElementById('btnSubmit');

function showAlert(kind, message) {
    alertMessage.textContent = message;
    alertMessage.className = `alert-message alert-${kind}`;
    alertMessage.style.display = 'block';
}

async function handleForgot(event) {
    event.preventDefault();
    alertMessage.style.display = 'none';

    const email = document.getElementById('email').value.trim();
    if (!email) {
        showAlert('error', 'Informe o e-mail da sua conta.');
        return;
    }

    btnSubmit.disabled = true;
    btnSubmit.textContent = 'Enviando...';

    try {
        const response = await fetch('/api/v1/auth/password/forgot', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email })
        });
        const data = await response.json();

        // A API responde igual exista ou não a conta; a tela só repete a mensagem dela.
        showAlert(response.ok ? 'success' : 'error', data.message || data.error || 'Não foi possível enviar agora.');
    } catch (error) {
        console.error('Erro na requisição:', error);
        showAlert('error', 'Erro ao conectar ao servidor. Tente novamente.');
    } finally {
        btnSubmit.disabled = false;
        btnSubmit.textContent = 'Enviar link';
    }
}

form.addEventListener('submit', handleForgot);

// Sinal de que os handlers estão ligados (ver login.js).
document.body.dataset.ready = 'true';
