# Steps to Reproduce 
To reproduce this Terraform + CI/CD (GitHub Actions) deployment to AWS EKS using ECR and blue-green strategy, follow these step-by-step instructions:

- **Step 1:** Clone github repository https://github.com/rehmanzafar/nodejs-hello-test.git
- **Step 2:** Navigate to **nodejs-hello-test -> eks-infra** and execute the following command in conole to prepare the required infrastructure.

```bash
# Provision AWS infrastructure
terraform init
terraform validate
terraform apply -target=module.vpc -target=module.eks
terraform apply -target=helm_release.cert_manager
terraform apply 
```
- **Step 3:** Set GitbHub secret environment variable to store sensitive information i.e. Amazon Account ID, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION. Please update information in your GitHub repo settings -> Actions secrets and variables -> Actions
- **Step 4:** Push code to the GitHub repository.
- **Step 5:** Once the application is deployed, get the external IP address. It can be retrieved by running the following command:
```bash
kubectl get svc nodejs-service -n default
```
- **Step 6:** Test the application
    - By default at homepage, you will see a message returned from the code 
    ```bash
    http://REPLACE WITH YOUR EXTERNAL IP
    ```
    - To check the health of the application, URL/health
    ```bash
    http://REPLACE WITH YOUR EXTERNAL IP/health
    ```
    - To check the version of the application, URL/version
    ```bash
    http://REPLACE WITH YOUR EXTERNAL IP/version
    ```

