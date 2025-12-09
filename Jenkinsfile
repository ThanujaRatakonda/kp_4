pipeline {
    agent any

    environment {
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        HARBOR_URL = "10.131.103.92:8090"
        HARBOR_PROJECT = "kp_4"
        TRIVY_OUTPUT_JSON = "trivy-output.json"
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['FULL_PIPELINE', 'SCALE_ONLY'],
            description: 'Run full pipeline or only scaling'
        )

        choice(
            name: 'SERVICE',
            choices: ['ALL', 'FRONTEND', 'BACKEND'],
            description: 'Which microservice to deploy'
        )

        string(name: 'REPLICA_COUNT', defaultValue: '1', description: 'Frontend & Backend replicas')
        string(name: 'DB_REPLICA_COUNT', defaultValue: '1', description: 'DB replicas')
    }

    stages {

        stage('Checkout') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                git 'https://github.com/ThanujaRatakonda/kp_4.git'
            }
        }

        stage('Build Docker Images') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {
                    def services = [
                        FRONTEND: [name: "frontend", folder: "frontend"],
                        BACKEND : [name: "backend",  folder: "backend"]
                    ]

                    services.each { key, svc ->
                        if (params.SERVICE == key || params.SERVICE == 'ALL') {
                            echo "Building image for ${svc.name}"
                            sh "docker build -t ${svc.name}:${IMAGE_TAG} ${svc.folder}"
                        }
                    }
                }
            }
        }

        stage('Scan Docker Images') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {
                    def services = [
                        FRONTEND: "frontend",
                        BACKEND : "backend"
                    ]

                    services.each { key, img ->
                        if (params.SERVICE == key || params.SERVICE == 'ALL') {
                            echo "Scanning ${img}:${IMAGE_TAG}"
                            sh """
                                trivy image ${img}:${IMAGE_TAG} \
                                --severity CRITICAL,HIGH \
                                --format json \
                                -o ${TRIVY_OUTPUT_JSON}
                            """

                            archiveArtifacts artifacts: "${TRIVY_OUTPUT_JSON}", fingerprint: true

                            def vul = sh(
                                script: """jq '[.Results[] |
                                    (.Packages // [] | .[]? | select(.Severity=="CRITICAL" or .Severity=="HIGH")) +
                                    (.Vulnerabilities // [] | .[]? | select(.Severity=="CRITICAL" or .Severity=="HIGH"))
                                ] | length' ${TRIVY_OUTPUT_JSON}""",
                                returnStdout: true
                            ).trim()

                            if (vul.toInteger() > 0) {
                                error "Critical/High vulnerabilities found in ${img}"
                            }
                        }
                    }
                }
            }
        }

        stage('Push Images to Harbor') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {
                    def services = [
                        FRONTEND: "frontend",
                        BACKEND : "backend"
                    ]

                    services.each { key, img ->
                        if (params.SERVICE == key || params.SERVICE == 'ALL') {

                            def fullImage = "${HARBOR_URL}/${HARBOR_PROJECT}/${img}:${IMAGE_TAG}"

                            withCredentials([usernamePassword(
                                credentialsId: 'harbor-creds',
                                usernameVariable: 'HARBOR_USER',
                                passwordVariable: 'HARBOR_PASS'
                            )]) {
                                sh "echo \$HARBOR_PASS | docker login ${HARBOR_URL} -u \$HARBOR_USER --password-stdin"
                                sh "docker tag ${img}:${IMAGE_TAG} ${fullImage}"
                                sh "docker push ${fullImage}"
                            }

                            // cleanup local image
                            sh "docker rmi ${img}:${IMAGE_TAG} || true"
                        }
                    }
                }
            }
        }

        stage('Apply Kubernetes Deployment') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {

                    if (params.SERVICE == 'FRONTEND' || params.SERVICE == 'ALL') {
                        sh "sed -i 's/__IMAGE_TAG__/${IMAGE_TAG}/g' k8s/frontend-deployment.yaml"
                        sh "kubectl apply -f k8s/frontend-deployment.yaml"
                        sh "kubectl apply -f k8s/frontend-service.yaml"
                    }

                    if (params.SERVICE == 'BACKEND' || params.SERVICE == 'ALL') {
                        sh "sed -i 's/__IMAGE_TAG__/${IMAGE_TAG}/g' k8s/backend-deployment.yaml"
                        sh "kubectl apply -f k8s/backend-deployment.yaml"
                        sh "kubectl apply -f k8s/backend-service.yaml"
                    }

                    // database only applied when ALL selected
                    if (params.SERVICE == 'ALL') {
                        sh "kubectl apply -f k8s/database-statefulset.yaml"
                        sh "kubectl apply -f k8s/database-service.yaml"
                    }
                }
            }
        }

        stage('Scale Deployments') {
            steps {
                script {
                    sh "kubectl scale deployment frontend --replicas=${params.REPLICA_COUNT} || true"
                    sh "kubectl scale deployment backend --replicas=${params.REPLICA_COUNT} || true"
                    sh "kubectl scale statefulset database --replicas=${params.DB_REPLICA_COUNT} || true"

                    sh "kubectl get deployments"
                }
            }
        }
    }
}
