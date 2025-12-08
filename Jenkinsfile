pipeline {
    agent any

    environment {
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        HARBOR_URL = "10.131.103.92:8090"
        HARBOR_PROJECT = "kp_4"
        TRIVY_OUTPUT_JSON = "trivy-output.json"
    }

    parameters {
        choice(name: 'ACTION', choices: ['FULL_PIPELINE', 'SCALE_ONLY'], description: 'FULL_PIPELINE or SCALE_ONLY')
        string(name: 'FRONTEND_REPLICAS', defaultValue: '1', description: 'Frontend replica count')
        string(name: 'BACKEND_REPLICAS', defaultValue: '1', description: 'Backend replica count')
        string(name: 'DB_REPLICAS', defaultValue: '1', description: 'Database replica count')
    }

    stages {

        /* =======================================
            CHECKOUT + CHANGE DETECTION
        ======================================= */
        stage('Checkout') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                git 'https://github.com/ThanujaRatakonda/kp_4.git'
                script {
                    def changedFiles = sh(script: "git diff --name-only HEAD~1 HEAD", returnStdout: true).trim()
                    env.FRONTEND_CHANGED = changedFiles.contains("frontend/") ? "true" : "false"
                    env.BACKEND_CHANGED  = changedFiles.contains("backend/")  ? "true" : "false"
                    echo "Frontend changed: ${env.FRONTEND_CHANGED}"
                    echo "Backend changed : ${env.BACKEND_CHANGED}"
                }
            }
        }

        /* =======================================
            STORAGE SETUP
        ======================================= */
        stage('Apply Storage') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                sh """
                    kubectl apply -f k8s/shared-storage-class.yaml
                    kubectl apply -f k8s/shared-pv.yaml
                    kubectl apply -f k8s/shared-pvc.yaml
                """
            }
        }

        /* =======================================
            DATABASE DEPLOYMENT
        ======================================= */
        stage('Deploy Database') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                sh "kubectl apply -f k8s/database-deployment.yaml"
            }
        }

        stage('Scale Database') {
            steps {
                sh "kubectl scale statefulset database --replicas=${params.DB_REPLICAS}"
            }
        }

        /* =======================================
            FRONTEND PIPELINE
        ======================================= */
        stage('Build Frontend') {
            when { expression { params.ACTION == 'FULL_PIPELINE' && env.FRONTEND_CHANGED == 'true' } }
            steps {
                sh "docker build -t frontend:${IMAGE_TAG} ./frontend"
            }
        }

        stage('Scan Frontend') {
            when { expression { params.ACTION == 'FULL_PIPELINE' && env.FRONTEND_CHANGED == 'true' } }
            steps {
                sh """
                    trivy image frontend:${IMAGE_TAG} \
                        --severity CRITICAL,HIGH \
                        --format json -o ${TRIVY_OUTPUT_JSON}
                """
                archiveArtifacts artifacts: "${TRIVY_OUTPUT_JSON}"
            }
        }

        stage('Push Frontend') {
            when { expression { params.ACTION == 'FULL_PIPELINE' && env.FRONTEND_CHANGED == 'true' } }
            steps {
                script {
                    def fullImg = "${HARBOR_URL}/${HARBOR_PROJECT}/frontend:${IMAGE_TAG}"
                    withCredentials([usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'U', passwordVariable: 'P')]) {
                        sh "echo \$P | docker login ${HARBOR_URL} -u \$U --password-stdin"
                        sh "docker tag frontend:${IMAGE_TAG} ${fullImg}"
                        sh "docker push ${fullImg}"
                    }
                }
            }
        }

        stage('Deploy Frontend') {
            when { expression { env.FRONTEND_CHANGED == 'true' } }
            steps {
                sh """
                    sed -i 's/__IMAGE_TAG__/${IMAGE_TAG}/g' k8s/frontend-deployment.yaml
                    kubectl apply -f k8s/frontend-deployment.yaml
                """
            }
        }

        stage('Scale Frontend') {
            steps {
                sh "kubectl scale deployment frontend --replicas=${params.FRONTEND_REPLICAS}"
            }
        }

        /* =======================================
            BACKEND PIPELINE
        ======================================= */
        stage('Build Backend') {
            when { expression { params.ACTION == 'FULL_PIPELINE' && env.BACKEND_CHANGED == 'true' } }
            steps {
                sh "docker build -t backend:${IMAGE_TAG} ./backend"
            }
        }

        stage('Scan Backend') {
            when { expression { params.ACTION == 'FULL_PIPELINE' && env.BACKEND_CHANGED == 'true' } }
            steps {
                sh """
                    trivy image backend:${IMAGE_TAG} \
                        --severity CRITICAL,HIGH \
                        --format json -o ${TRIVY_OUTPUT_JSON}
                """
                archiveArtifacts artifacts: "${TRIVY_OUTPUT_JSON}"
            }
        }

        stage('Push Backend') {
            when { expression { params.ACTION == 'FULL_PIPELINE' && env.BACKEND_CHANGED == 'true' } }
            steps {
                script {
                    def fullImg = "${HARBOR_URL}/${HARBOR_PROJECT}/backend:${IMAGE_TAG}"
                    withCredentials([usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'U', passwordVariable: 'P')]) {
                        sh "echo \$P | docker login ${HARBOR_URL} -u \$U --password-stdin"
                        sh "docker tag backend:${IMAGE_TAG} ${fullImg}"
                        sh "docker push ${fullImg}"
                    }
                }
            }
        }

        stage('Deploy Backend') {
            when { expression { env.BACKEND_CHANGED == 'true' } }
            steps {
                sh """
                    sed -i 's/__IMAGE_TAG__/${IMAGE_TAG}/g' k8s/backend-deployment.yaml
                    kubectl apply -f k8s/backend-deployment.yaml
                """
            }
        }

        stage('Scale Backend') {
            steps {
                sh "kubectl scale deployment backend --replicas=${params.BACKEND_REPLICAS}"
            }
        }

    } 
}

