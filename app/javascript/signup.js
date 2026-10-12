const form = document.getElementById('signupForm');
const alertMessage = document.getElementById('alertMessage');
const btnSubmit = document.getElementById('btnSubmit');

function showAlert(kind, message) {
    alertMessage.textContent = message;
    alertMessage.className = `alert-message alert-${kind}`;
    alertMessage.style.display = 'block';
}

function hideAlert() {
    alertMessage.style.display = 'none';
    alertMessage.className = 'alert-message';
}

async function handleSignup(event) {
    event.preventDefault();
    hideAlert();

    const email = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;
    const passwordConfirmation = document.getElementById('passwordConfirmation').value;

    // Confere já no navegador para poupar uma ida ao servidor; o servidor valida de novo.
    if (password !== passwordConfirmation) {
        showAlert('error', 'As senhas não conferem.');
        return;
    }

    btnSubmit.disabled = true;
    btnSubmit.textContent = 'Criando conta...';

    try {
        const response = await fetch('/api/v1/auth/signup', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email, password, password_confirmation: passwordConfirmation })
        });
        const data = await response.json();

        if (response.ok) {
            // A sessão já foi aberta pelo servidor (cookie HttpOnly).
            showAlert('success', 'Conta criada! Redirecionando...');
            setTimeout(() => { window.location.href = '/dashboard'; }, 800);
            return;
        }

        const message = data.errors ? data.errors.join(' • ') : (data.error || 'Não foi possível criar a conta.');
        showAlert('error', message);
    } catch (error) {
        console.error('Erro na requisição:', error);
        showAlert('error', 'Erro ao conectar ao servidor. Tente novamente.');
    }

    btnSubmit.disabled = false;
    btnSubmit.textContent = 'Criar conta';
}

form.addEventListener('submit', handleSignup);

// Sinal de que os handlers estão ligados (ver login.js).
document.body.dataset.ready = 'true';
