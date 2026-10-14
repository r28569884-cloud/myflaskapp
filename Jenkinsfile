pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }

    environment {
        PYTHON_EXE = 'C:\\Users\\Ray\\AppData\\Local\\Programs\\Python\\Python312\\python.exe'
        VENV_PYTHON = '.venv\\Scripts\\python.exe'
        PYTHONUTF8 = '1'
        PIP_DISABLE_PIP_VERSION_CHECK = '1'
    }

    stages {
        stage('Verify Python Path') {
            steps {
                bat 'whoami'
                bat '"%PYTHON_EXE%" --version'
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Fix pip') {
            steps {
                bat '"%PYTHON_EXE%" -m venv .venv'
                bat '"%VENV_PYTHON%" -m ensurepip --upgrade'
                bat '"%VENV_PYTHON%" -m pip --version'
            }
        }

        stage('Install Dependencies') {
            steps {
                bat '"%VENV_PYTHON%" -m pip install --timeout 60 --retries 3 -r requirements.txt pyinstaller==6.22.3'
                bat '"%VENV_PYTHON%" -m pip check'
            }
        }

        stage('Lint') {
            steps {
                bat '"%VENV_PYTHON%" -m flake8 app.py tests/'
            }
        }

        stage('Test') {
            steps {
                bat '"%VENV_PYTHON%" -m pytest tests/ -v --cov=app --cov-report=term-missing --cov-report=html:htmlcov --junitxml=test-results.xml'
            }
        }

        stage('Build') {
            steps {
                bat '"%VENV_PYTHON%" -m PyInstaller --noconfirm --clean --onefile app.py'
                archiveArtifacts artifacts: 'dist/app.exe', fingerprint: true
            }
        }

        stage('Deploy') {
            steps {
                powershell ' & "./deploy.ps1" '
            }
        }
    }

    post {
        always {
            script {
                if (fileExists('test-results.xml')) {
                    archiveArtifacts artifacts: 'test-results.xml', fingerprint: false
                }
                if (fileExists('htmlcov/index.html')) {
                    publishHTML(target: [
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'htmlcov',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }
        success {
            echo 'CI/CD succeeded. Open http://127.0.0.1:5000/'
        }
    }
}
