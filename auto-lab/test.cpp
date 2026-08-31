#include <stdio.h>

int main() {

    // Food prices
    int pizza_price = 100;
    int burger_price = 80;

    // Amount bought
    int pizza_bought = 0;
    int burger_bought = 0;

    // Total cost
    int total_cost = 0;

    int choice;

    // Greeting
    printf("================================\n");
    printf("     WELCOME TO HONSOC'S SHOP!\n");
    printf("================================\n");



        printf("\nMENU:\n");
        printf("1. Pizza  - P%d\n", pizza_price);
        printf("2. Burger - P%d\n", burger_price);

        printf("\nOrder 1 of 3");
        printf("\nChoose an item: ");
        scanf("%d", &choice);

        if (choice == 1) {
            pizza_bought++;
            printf("Pizza added to your order!\n");
        }
        else if (choice == 2) {
            burger_bought++;
            printf("Burger added to your order!\n");
        }
        else {
            printf("Invalid choice! No item was added.\n");
        }

        printf("\nOrder 2 of 3");
        printf("\nChoose an item: ");
        scanf("%d", &choice);

        if (choice == 1) {
            pizza_bought++;
            printf("Pizza added to your order!\n");
        }
        else if (choice == 2) {
            burger_bought++;
            printf("Burger added to your order!\n");
        }
        else {
            printf("Invalid choice! No item was added.\n");
        }

        printf("\nOrder 3 of 3");
        printf("\nChoose an item: ");
        scanf("%d", &choice);

        if (choice == 1) {
            pizza_bought++;
            printf("Pizza added to your order!\n");
        }
        else if (choice == 2) {
            burger_bought++;
            printf("Burger added to your order!\n");
        }
        else {
            printf("Invalid choice! No item was added.\n");
        }
    

    // Calculate total
    total_cost = (pizza_price * pizza_bought)
               + (burger_price * burger_bought);

    // Display order summary
    printf("\n================================\n");
    printf("         ORDER SUMMARY\n");
    printf("================================\n");

    printf("Pizza bought : %d\n", pizza_bought);
    printf("Burger bought: %d\n", burger_bought);

    printf("\nTOTAL COST: P%d\n", total_cost);
    printf("Thank you for ordering!\n");

    return 0;
}