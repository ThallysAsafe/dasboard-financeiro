const form = document.getElementById('resetForm');
const alertMessage = document.getElementById('alertMessage');
const btnSubmit = document.getElementById('btnSubmit');

// O token vem na URL do e-mail. Lê e tira da barra de endereço na hora: assim não fica no
// histórico do navegador nem vai em um Referer. A troca só acontece por POST.
const token = new URLSearchParams(window.location.search).get('token');
window.history.replaceState(null, '', window.location.pathname);

function showAlert(kind, message) {
    alertMessage.textContent = message;
    alertMessage.className = `alert-message alert-${kind}`;
    alertMessage.style.display = 'block';
}

function showInvalidLink(message) {
    showAlert('error', message);
    form.classList.add('is-hidden');
    document.getElementById('invalidLink').classList.remove('is-hidden');
}

async function handleReset(event) {
    event.preventDefault();
    alertMessage.style.display = 'none';

    const password = document.getElementById('password').value;
    const confirmation = document.getElementById('passwordConfirmation').value;

    if (password !== confirmation) {
        showAlert('error', 'As senhas não conferem.');
        return;
    }

    btnSubmit.disabled = true;
    btnSubmit.textContent = 'Salvando...';

    try {
        const response = await fetch('/api/v1/auth/password/reset', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token, password, password_confirmation: confirmation })
        });
        const data = await response.json();

        if (response.ok) {
            showAlert('success', data.message);
            form.classList.add('is-hidden');
            document.getElementById('afterReset').classList.remove('is-hidden');
            return;
        }

        // Link inválido/expirado não tem como ser corrigido digitando de novo: pede outro.
        if (data.error) {
            showInvalidLink(data.error);
        } else {
            showAlert('error', (data.errors || ['Não foi possível trocar a senha.']).join(' • '));
        }
    } catch (error) {
        console.error('Erro na requisição:', error);
        showAlert('error', 'Erro ao conectar ao servidor. Tente novamente.');
    }

    btnSubmit.disabled = false;
    btnSubmit.textContent = 'Salvar nova senha';
}

form.addEventListener('submit', handleReset);

if (!token) showInvalidLink('Link inválido. Peça um novo.');

// Sinal de que os handlers estão ligados (ver login.js).
document.body.dataset.ready = 'true';
